# 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md

**OPS Software Bible — Complete Job Lifecycle: Inquiry → Close**

**Purpose**: Defines the complete data flow for a trade job from first contact through to a paid invoice. Documents all entity relationships, automation triggers, new entities, and required changes to existing entities. This is the master reference for how leads, pipeline, clients, estimates, projects, tasks, and invoices inter-operate.

**Last Updated**: March 16, 2026
**Designed With**: ops-web codebase + ops-software-bible review session

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Complete Flow Overview](#complete-flow-overview)
3. [Pipeline: The Job Spine](#pipeline-the-job-spine)
4. [Data Model Changes (Modified Entities)](#data-model-changes-modified-entities)
5. [New Entities](#new-entities)
6. [Automation Rules & Triggers](#automation-rules--triggers)
7. [Communication Logging](#communication-logging)
8. [Site Visits](#site-visits)
9. [Project Photos](#project-photos)
10. [Email Pipeline Integration](#email-pipeline-integration)
11. [Entity Relationship Map](#entity-relationship-map)
12. [Status & Stage Reference](#status--stage-reference)
13. [Implementation Notes](#implementation-notes)

---

## Design Philosophy

### Project = Folder

A **Project** is a folder that organizes all work for a client job. It can contain:
- Multiple estimates (original scope, phases, revisions)
- Tasks generated from approved estimates
- Photos (site visit, in-progress, completion)
- Invoices tied to approved estimates

**Project total value** = sum of all approved estimates within the project.

### Estimate = The Contract

An estimate is the primary financial document. It drives everything downstream:
- Sending an estimate triggers client + project creation
- Approving an estimate triggers task generation
- An approved estimate converts to an invoice

### Pipeline = The Command Center

The pipeline Kanban board is not just a CRM view — it is the active workflow driver for the entire pre-win lifecycle. Stage transitions are triggered by real actions (sending an estimate, getting a reply), not just manual drags.

### Zero Duplicate Entry

A user should never have to enter the same information twice:
- Estimate line items → tasks (auto-generated, no re-entry)
- Opportunity contact → client (auto-created on first estimate send)
- Opportunity + estimate → project (auto-created on first estimate send)
- Approved estimate → invoice (direct conversion, no re-entry)
- Site visit photos → project photos (auto-attached on job win)

---

## Complete Flow Overview

```
LEAD ENTERS PIPELINE
  Sources: web form, manual entry, email log, Gmail auto-detection
       │
       ▼
Opportunity (new_lead)
  contactName, contactEmail, contactPhone
  source, estimatedValue (rough), notes
  NO clientId yet — client may not exist
       │
       │  first activity logged [AUTO-ADVANCE]
       ▼
Opportunity (qualifying)
  Site visit may be booked here
  Follow-up reminders created
       │
       │  user creates estimate [AUTO-ADVANCE]
       ▼
Opportunity (quoting)
  Estimate(draft) linked to opportunityId
  Line items built:
    [LABOR]    Deck Renovation $12,000  → taskTypeId: "Deck Work"
    [LABOR]    Picket Railing $5,000    → taskTypeId: "Railing"
    [MATERIAL] Lumber $3,500            → no task
    [OTHER]    Permit Fee $150          → no task
       │
       │  user clicks "Send Estimate"
       │
       ▼  ══════════════════════════════
          SEND FLOW — two inline prompts

          STEP 1 — Client
          "Who is this estimate for?"
          → user types name
          → auto-suggests existing clients from DB
          → select existing OR confirm "New Client: [name]"
          → Client auto-created from opportunity contact info
          → estimate.clientId = client.id
          → opportunity.clientId = client.id

          STEP 2 — Project
          "File into a project?"
          → search existing projects OR create new
          → if new: Project auto-created
              (title, clientId, status=RFQ, opportunityId)
          → estimate.projectId = project.id
          → opportunity.projectId = project.id
          ══════════════════════════════
       │
       │  estimate sent [AUTO-ADVANCE]
       ▼
Opportunity (quoted)
Project (Estimated)
  Pipeline card now shows PROJECT data:
    - Project name + client
    - Pending estimate value
    - Estimates: 1 total, 0 approved
       │
       │  X days pass, no client response [AUTO-ADVANCE]
       │  FollowUp reminder auto-created
       ▼
Opportunity (follow_up)
       │
       │  client replies (inbound activity logged) [AUTO-ADVANCE]
       ▼
Opportunity (negotiation)
  Client has questions or wants changes
  Staff may create a new estimate for same project (v2 scenario)
  New estimate sent → loops back to (quoted)
       │
       │  estimate approved [AUTO-ADVANCE]
       ▼
Opportunity (won)
Project (Accepted)
       │
       ▼  ══════════════════════════════
          TASK GENERATION MODAL
          (skippable if company toggle: "Auto-generate tasks")

          "Review Tasks for: Deck Renovation"

          Deck Renovation — $12,000
            [x] Footings           crew: John, Mike  [edit]
            [x] Framing            crew: John, Mike  [edit]
            [x] Vinyl Membrane     crew: John        [edit]
            [+ Add task to this item]

          Picket Railing — $5,000
            [x] Picket Railing Install  crew: Sarah  [edit]
            [+ Add task to this item]

          [Confirm & Create Tasks]
          ══════════════════════════════
       │
       ▼
ProjectTasks created (status: Booked)
  Each task stores: sourceLineItemId, sourceEstimateId
       │
       │  tasks scheduled (dates stored on ProjectTask)
       ▼
Task startDate/endDate set
       │  first task starts
       ▼
Project (InProgress)
       │  all tasks complete
       ▼
Project (Completed)
       │
       ▼  ══════════════════════════════
          INVOICE CREATION
          Convert Estimate → Invoice (1:1)
          invoice.projectId = project.id
          invoice.estimateId = estimate.id
          Partial payments supported on single invoice:
            Payment 1: Deposit   (e.g. 40%)
            Payment 2: Progress  (e.g. 30%)
            Payment 3: Final     (e.g. 30%)
          ══════════════════════════════
       │
       │  invoice fully paid
       ▼
Project (Closed)
```

---

## Pipeline: The Job Spine

### Stage-by-Stage Reference

#### `new_lead`
**How leads enter:**
- Manual entry by office staff
- Web inquiry form submission (auto-creates Opportunity)
- Staff logs a call/email (creates Opportunity from that log)
- Gmail integration — unrecognized inquiry email surfaced for staff review → "Create Lead"

**Card shows:** Contact name, source badge, rough estimated value, age in stage

**Auto-advance trigger:** First Activity logged → `qualifying`

---

#### `qualifying`
Staff is assessing scope. Site visit may be booked.

**Actions available from card:**
- Log activity (call, meeting, site visit)
- Book site visit (creates SiteVisit — scheduling dates stored on the visit/task directly; CalendarEvent model has been removed)
- Create follow-up reminder
- Update estimated value as scope clarifies

**Card shows:** Last activity, next follow-up date, days in stage

**Auto-advance trigger:** User creates an Estimate from this opportunity → `quoting`

---

#### `quoting`
An estimate draft is actively being built.

**Card shows:** Estimate draft value, last edited, line item count

**Auto-advance trigger:** Estimate is sent → triggers Send Flow → `quoted`

---

#### `quoted`
Estimate sent. Client + Project now exist.

**Card shows (PROJECT DATA):**
```
┌──────────────────────────────┐
│ Smith Deck Job               │
│ John Smith                   │
│ ──────────────────────────── │
│ $17,650  ← pending           │
│ 1 estimate / 0 approved      │
│ Sent: 2 days ago             │
└──────────────────────────────┘
```

**Auto-advance trigger:** X days pass with no client response → `follow_up`
- X is configurable: `CompanySettings.followUpReminderDays` (default: 3)
- FollowUp record auto-created: *"Follow up on Estimate #EST-0042 — sent 3 days ago"*
- type: `quote_follow_up`, isAutoGenerated: true

---

#### `follow_up`
Waiting on client. System has nudged staff.

**Card shows:** Days since estimate sent, follow-up due date

**Auto-advance trigger:** Inbound Activity logged (client reply via email, call, text) → `negotiation`

**Manual override:** Staff can drag back to `quoted` or forward to `negotiation`

---

#### `negotiation`
Client has replied but not approved. Price or scope discussion in progress.

**Actions available:**
- Create a new estimate on the same project (revision scenario)
- Log activities (call notes, meeting notes)
- Update expected close date

**Card shows:** Number of estimate versions, latest estimate value

**Auto-advance trigger:** Revised estimate sent → `quoted` (loops back)

**Manual advance:** Drag to `won` for verbal approval before formal estimate sign-off

---

#### `won`
Estimate approved. Project goes live.

**What happens automatically:**
1. `opportunity.stage = won`
2. `opportunity.actualCloseDate = now`
3. `project.status = Accepted`
4. Site visit photos → auto-attached to project as ProjectPhotos (source: `site_visit`)
5. Task Generation modal opens (or silent auto-generate if toggle enabled)

**Card shows (PROJECT DATA):**
```
┌──────────────────────────────┐
│ Smith Deck Job          ✓ WON│
│ John Smith                   │
│ ──────────────────────────── │
│ $15,500  approved            │
│ 2 estimates / 1 approved     │
│ Tasks: 5 / 0 complete        │
│ → View Project               │
└──────────────────────────────┘
```

**Won column behavior:** Shows jobs won within last 30/60/90 days (configurable). Acts as a handoff confirmation before the project fully graduates to the Projects section.

---

#### `lost`
Estimate declined or opportunity abandoned.

**What happens:**
- Prompt for lost reason (uses existing `LOSS_REASONS` list)
- `opportunity.actualCloseDate = now`
- Opportunity soft-deleted (preserved for reporting)
- All activities, estimates, and stage transitions remain in history

---

### Pipeline Card Data by Stage

| Stage | Key Data Shown |
|---|---|
| `new_lead` | Contact name, source, estimated value, age |
| `qualifying` | Last activity, next follow-up |
| `quoting` | Draft estimate value, last edited |
| `quoted` | Project name, pending estimate value, sent date |
| `follow_up` | Days since sent, follow-up due |
| `negotiation` | # estimate versions, latest value |
| `won` | Project name, approved value, task progress |
| `lost` | Contact name, lost reason, estimated value lost |

### Stage Auto-Advance Summary

| Trigger | From | To |
|---|---|---|
| First Activity logged | `new_lead` | `qualifying` |
| Estimate created (draft) | `new_lead` or `qualifying` | `quoting` |
| Estimate sent | `quoting` | `quoted` |
| X days no response (configurable) | `quoted` | `follow_up` |
| Inbound Activity logged | `quoted` or `follow_up` | `negotiation` |
| Revised estimate sent | `negotiation` | `quoted` |
| Estimate approved | any active stage | `won` |
| Estimate declined | any active stage | `lost` (with prompt) |

All auto-advances record a `StageTransition` row. Users can manually drag to any stage at any time (existing Kanban behavior preserved).

---

## Data Model Changes (Modified Entities)

### `LineItem` (Supabase) — MODIFIED

Add `type`, `taskTypeId`, and `estimatedHours`:

```typescript
type LineItemType = 'LABOR' | 'MATERIAL' | 'OTHER'

interface LineItem {
  // --- existing fields ---
  id: string;
  estimateId: string | null;
  invoiceId: string | null;
  description: string;
  quantity: number;
  unit: string | null;
  unitPrice: number;
  discount: number;          // percentage
  taxable: boolean;
  productId: string | null;  // optional link to product catalog
  displayOrder: number;

  // --- NEW fields ---
  type: LineItemType;                  // LABOR | MATERIAL | OTHER
  taskTypeId: string | null;           // Bubble TaskType ID — LABOR items only
  estimatedHours: number | null;       // optional, for labor costing
}
```

**Rules:**
- `type` defaults to `LABOR` when linked from a Product with `type = 'LABOR'`
- Only `LABOR` line items participate in task generation
- `MATERIAL` and `OTHER` items are billing-only — no tasks created
- `taskTypeId` is nullable: a LABOR item without a taskTypeId generates one generic task

---

### `TaskType` (Bubble) — MODIFIED

Add `defaultTeamMemberIds`:

```typescript
interface TaskType {
  // --- existing fields ---
  id: string;
  display: string;
  color: string;
  icon: string;              // SF Symbol name
  isDefault: boolean;
  displayOrder: number;
  companyId: string;
  deletedAt: Date | null;

  // --- NEW field ---
  defaultTeamMemberIds: string[];  // TeamMember IDs — default crew for this task type
}
```

**Usage:** When a task is auto-generated from a line item, it inherits `TaskType.defaultTeamMemberIds`. Users can override at the individual task level in the Review Tasks modal.

---

### `ProjectTask` (Bubble) — MODIFIED

Add traceability fields:

```typescript
interface ProjectTask {
  // --- existing fields ---
  id: string;
  projectId: string;
  companyId: string;
  taskTypeId: string | null;
  status: TaskStatus;          // Booked | InProgress | Completed | Cancelled
  customTitle: string | null;
  taskNotes: string | null;
  taskColor: string | null;
  calendarEventId: string | null;
  teamMemberIds: string[];
  displayOrder: number;
  deletedAt: Date | null;

  // --- NEW fields ---
  sourceLineItemId: string | null;   // Supabase LineItem ID that generated this task
  sourceEstimateId: string | null;   // Supabase Estimate ID that generated this task
}
```

**Usage:** Enables traceability — from any task, you can trace back to the exact estimate line item and estimate that created it. Useful for scope change tracking and audit history.

---

### `Project` (Bubble) — MODIFIED

Add opportunity linkage:

```typescript
interface Project {
  // --- existing fields ---
  id: string;
  title: string;
  status: ProjectStatus;     // RFQ | Estimated | Accepted | InProgress | Completed | Closed | Archived
  clientId: string | null;
  companyId: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  startDate: Date | null;
  endDate: Date | null;
  duration: number | null;
  notes: string | null;
  teamMemberIds: string[];
  defaultProjectColor: string | null;
  deletedAt: Date | null;

  // --- NEW field ---
  opportunityId: string | null;  // Supabase Opportunity ID — trace back to the originating lead
}
```

**Note:** `projectImages` (comma-separated string) is deprecated in favor of the new `ProjectPhoto` entity. See [Project Photos](#project-photos).

---

### `CalendarEvent` (Bubble) — REMOVED

> **NOTE:** The `CalendarEvent` model has been fully removed from the iOS codebase. Scheduling dates are now stored directly on `ProjectTask` (via `startDate`/`endDate` properties). Project dates are computed from their child tasks. The schema below is retained as historical reference for the Bubble backend, which may still have this data type.

```typescript
// REMOVED — Historical reference only.
// Scheduling is now task-based: ProjectTask.startDate / ProjectTask.endDate.
// Site visit scheduling uses SiteVisit entity directly.

type CalendarEventType = 'task' | 'site_visit' | 'other'

interface CalendarEvent {
  // --- existing fields (now optional where marked) ---
  id: string;
  companyId: string;
  title: string;
  color: string | null;
  startDate: Date;
  endDate: Date;
  duration: number | null;
  teamMemberIds: string[];
  deletedAt: Date | null;

  // Previously required — now optional
  projectId: string | null;       // null for pre-project site visits
  taskId: string | null;          // null for site visit events

  // --- NEW fields ---
  eventType: CalendarEventType;   // 'task' | 'site_visit' | 'other'
  opportunityId: string | null;   // for pre-project calendar events
  siteVisitId: string | null;     // links to SiteVisit record
}
```

---

### `Estimate` (Supabase) — MODIFIED

Add project linkage:

```typescript
interface Estimate {
  // --- existing fields ---
  id: string;
  companyId: string;
  clientId: string | null;
  opportunityId: string | null;
  title: string;
  estimateNumber: string;        // EST-0001, EST-0002...
  status: EstimateStatus;
  issueDate: Date;
  expirationDate: Date | null;
  lineItems: LineItem[];
  optionalItems: LineItem[];
  depositSchedule: DepositSchedule | null;
  paymentMilestones: PaymentMilestone[];
  totalAmount: number;
  taxAmount: number;
  discountAmount: number;
  pdfStoragePath: string | null;
  version: number;
  parentId: string | null;       // for revision history
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW field ---
  projectId: string | null;      // Bubble Project ID — which project this estimate belongs to
}
```

**Rules:**
- `projectId` is null until estimate is sent (filing into project is part of the Send Flow)
- A project can have multiple estimates (multiple scopes, phases, revisions)
- Project total value = `SUM(totalAmount) WHERE status = 'approved'`

---

### `Invoice` (Supabase) — MODIFIED

Add project and estimate linkage:

```typescript
interface Invoice {
  // --- existing fields ---
  id: string;
  companyId: string;
  clientId: string | null;
  invoiceNumber: string;         // INV-0001...
  status: InvoiceStatus;
  issueDate: Date;
  dueDate: Date | null;
  paymentTerms: string | null;
  lineItems: InvoiceLineItem[];
  amountDue: number;
  amountPaid: number;            // maintained by DB trigger
  balance: number;               // maintained by DB trigger
  payments: Payment[];
  notes: string | null;
  pdfStoragePath: string | null;
  voidedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW fields ---
  projectId: string | null;      // Bubble Project ID
  estimateId: string | null;     // Supabase Estimate ID this was converted from
}
```

---

### `Product` (Supabase) — MODIFIED

Add type and task type linkage to enable catalog-driven task auto-fill:

```typescript
interface Product {
  // --- existing fields ---
  id: string;
  companyId: string;
  name: string;
  description: string | null;
  category: string | null;
  defaultPrice: number;
  unitCost: number | null;
  unit: string | null;
  taxable: boolean;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;

  // --- NEW fields ---
  type: LineItemType;             // LABOR | MATERIAL | OTHER — auto-sets line item type
  taskTypeId: string | null;      // Bubble TaskType ID — auto-sets task type on line item
}
```

**Usage:** When a user adds a product from the catalog to an estimate, `product.type` and `product.taskTypeId` automatically populate the line item. Zero manual configuration per estimate.

---

### `Opportunity` (Supabase) — MODIFIED

Add Gmail source field:

```typescript
interface Opportunity {
  // --- existing fields (unchanged) ---
  id: string;
  companyId: string;
  clientId: string | null;
  title: string;
  description: string | null;
  contactName: string | null;
  contactEmail: string | null;
  contactPhone: string | null;
  stage: OpportunityStage;
  source: OpportunitySource | null;
  assignedTo: string | null;
  priority: OpportunityPriority | null;
  estimatedValue: number | null;
  actualValue: number | null;
  winProbability: number;
  expectedCloseDate: Date | null;
  actualCloseDate: Date | null;
  stageEnteredAt: Date;
  projectId: string | null;
  lostReason: string | null;
  lostNotes: string | null;
  address: string | null;
  lastActivityAt: Date | null;
  nextFollowUpAt: Date | null;
  tags: string[];
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW field ---
  sourceEmailId: string | null;   // Gmail message ID — set when opportunity created from Gmail
}
```

---

### `Activity` (Supabase) — MODIFIED

Add email threading, attachment support, and site visit linkage:

```typescript
interface Activity {
  // --- existing fields ---
  id: string;
  companyId: string;
  opportunityId: string | null;
  clientId: string | null;
  estimateId: string | null;
  invoiceId: string | null;
  type: ActivityType;
  subject: string | null;
  content: string | null;
  outcome: string | null;
  direction: 'inbound' | 'outbound' | null;
  durationMinutes: number | null;
  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW fields ---
  attachments: string[];            // S3 URLs — email attachments, documents
  emailThreadId: string | null;     // Gmail thread ID — groups email chain together
  emailMessageId: string | null;    // Gmail message ID — prevents duplicate auto-logging
  isRead: boolean;                  // false for auto-logged inbound, true for manual entry
  siteVisitId: string | null;       // set if auto-created from a SiteVisit completion
  projectId: string | null;         // direct link to project (for post-win activities)
}
```

**New `ActivityType` values to add:**
- `site_visit` — a scheduled/completed site visit
- `site_visit_scheduled` — system event when site visit is booked

---

### `CompanySettings` (Supabase) — MODIFIED / NEW TABLE

Extend (or create if not exists) to support lifecycle configuration:

```typescript
interface CompanySettings {
  companyId: string;                        // Primary key (1:1 with Company)

  // Task generation
  autoGenerateTasks: boolean;               // Skip review modal on estimate approval (default: false)

  // Follow-up automation
  followUpReminderDays: number;             // Days before auto-moving to follow_up stage (default: 3)

  // Gmail
  gmailAutoLogEnabled: boolean;             // Auto-log emails from connected Gmail accounts (default: true)

  createdAt: Date;
  updatedAt: Date;
}
```

---

## New Entities

### `TaskTemplate` (Bubble) — NEW

Defines the default tasks that are proposed when a LABOR line item is tagged with a TaskType. This is what enables "Deck Renovation → [Footings, Framing, Vinyl Membrane]" without any manual input per estimate.

```typescript
interface TaskTemplate {
  id: string;
  companyId: string;
  taskTypeId: string;                   // parent TaskType
  title: string;                        // e.g., "Footings", "Framing", "Vinyl Membrane"
  description: string | null;           // optional instructions
  estimatedHours: number | null;        // optional, for scheduling hints
  displayOrder: number;                 // controls order in Review Tasks modal
  defaultTeamMemberIds: string[];       // overrides TaskType.defaultTeamMemberIds if non-empty
  deletedAt: Date | null;
}
```

**Example data:**
```
TaskType: "Deck Work"
  TaskTemplate 1: "Footings"         order: 1  crew: [John, Mike]
  TaskTemplate 2: "Framing"          order: 2  crew: [John, Mike]
  TaskTemplate 3: "Vinyl Membrane"   order: 3  crew: [John]

TaskType: "Railing"
  TaskTemplate 1: "Picket Railing Install"  order: 1  crew: [Sarah]
```

**Task generation logic:**
```
For each LABOR lineItem in approved estimate:
  taskType = getTaskType(lineItem.taskTypeId)
  templates = getTaskTemplates(lineItem.taskTypeId)  // ordered by displayOrder

  if templates.length > 0:
    for each template in templates:
      proposeTask({
        title: template.title,
        taskTypeId: lineItem.taskTypeId,
        teamMemberIds: template.defaultTeamMemberIds.length > 0
                       ? template.defaultTeamMemberIds
                       : taskType.defaultTeamMemberIds,
        sourceLineItemId: lineItem.id,
        sourceEstimateId: estimate.id
      })
  else:
    // No templates: propose one generic task
    proposeTask({
      title: lineItem.description,
      taskTypeId: lineItem.taskTypeId,
      teamMemberIds: taskType?.defaultTeamMemberIds ?? [],
      sourceLineItemId: lineItem.id,
      sourceEstimateId: estimate.id
    })
```

---

### `ActivityComment` (Supabase) — NEW

Threaded comments on any Activity entry. Internal-only (staff eyes only). Supports future client portal visibility via `isClientVisible` flag.

```typescript
interface ActivityComment {
  id: string;
  companyId: string;
  activityId: string;                   // parent Activity
  userId: string;                       // author
  content: string;                      // plain text or markdown
  isClientVisible: boolean;             // always false for now — future portal
  createdAt: Date;
  updatedAt: Date | null;
  deletedAt: Date | null;
}
```

**UI pattern:**
```
Activity: Sent Estimate #042 to John Smith        ● 2 hours ago
  "Hi John, please find your estimate attached..."
  ────────────────────────────────────────────────
  [INTERNAL] Sarah: "He asked about timeline"
  [INTERNAL] John: "Told him 3 weeks, he's ok"
  [+ Add comment...]
```

**Rules:**
- Any staff member can comment on any activity
- Comments are soft-deleted (preserving audit trail)
- No notifications in v1 — comments are passive notes

---

### `SiteVisit` (Supabase) — NEW

A scheduled or ad-hoc visit to a job site for scope assessment, client meeting, or project check-in. Can exist before a project (on an Opportunity) or after (on a Project).

> **iOS status**: The `SiteVisit` SwiftData model exists (`OPS/OPS/DataModels/Supabase/SiteVisit.swift`) but no dedicated iOS views have been built yet. The site visit UI described below is design spec only at this time.

```typescript
type SiteVisitStatus = 'scheduled' | 'in_progress' | 'completed' | 'cancelled'

interface SiteVisit {
  id: string;
  companyId: string;
  opportunityId: string | null;     // pre-win: linked to opportunity
  projectId: string | null;         // post-win: linked to project
  clientId: string | null;          // denormalized for easy filtering

  // Scheduling
  scheduledAt: Date;
  durationMinutes: number;          // default: 60
  assigneeIds: string[];            // TeamMember IDs attending

  // Lifecycle
  status: SiteVisitStatus;          // scheduled → in_progress → completed | cancelled
  completedAt: Date | null;

  // On-site capture
  notes: string | null;             // scope observations (visible to staff)
  internalNotes: string | null;     // private staff notes (never shared)
  measurements: string | null;      // free-form: "Deck 400sqft, 14ft × 28ft, 6 posts"
  photos: string[];                 // S3 URLs captured on-site

  // Links created on completion
  activityId: string | null;        // auto-created Activity when status → completed
  calendarEventId: string | null;   // the calendar entry for this visit

  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

**Site visit lifecycle:**
```
BOOK SITE VISIT (from Opportunity card or Calendar)
  → SiteVisit created (status: scheduled)
  → SiteVisit scheduled (scheduling dates stored on SiteVisit/task directly; CalendarEvent model removed)
  → Activity auto-logged: "Site visit scheduled — Feb 20 @ 10am"
  → Opportunity stage → qualifying (if currently new_lead)

ON-SITE (staff opens visit on mobile/web)
  → SiteVisit.status → in_progress
  → Staff adds photos (camera or gallery)
  → Staff fills notes, measurements

MARK COMPLETE
  → SiteVisit.status → completed, completedAt = now
  → Activity auto-created on Opportunity timeline:
      type: site_visit
      subject: "Site visit completed"
      content: siteVisit.notes (preview)
      siteVisitId: siteVisit.id
  → Opportunity stage prompt: "Ready to build estimate?"
    → if Yes → creates Estimate (draft) → stage → quoting

JOB WON (opportunity converts to project)
  → For each photo in siteVisit.photos:
      ProjectPhoto created (source: 'site_visit', siteVisitId: siteVisit.id)
  → Photos appear in project gallery under "Site Visit" group
```

**SiteVisitService methods:**
- `createSiteVisit(data)` — creates visit + calendar event + activity
- `startSiteVisit(id)` — status → in_progress
- `completeSiteVisit(id, data)` — status → completed, creates completion activity
- `cancelSiteVisit(id)` — status → cancelled
- `uploadSiteVisitPhoto(id, file)` — uploads to S3, appends URL to photos[]
- `fetchSiteVisitsForOpportunity(opportunityId)` — all visits for a lead
- `fetchSiteVisitsForProject(projectId)` — all visits for a project

---

### `ProjectPhoto` (Supabase) — NEW

Replaces the `Project.projectImages` comma-separated string. Enables photos to be source-tagged, grouped in the gallery, and traced back to site visits.

```typescript
type PhotoSource = 'site_visit' | 'in_progress' | 'completion' | 'other'

interface ProjectPhoto {
  id: string;
  projectId: string;                // Bubble Project ID
  companyId: string;
  url: string;                      // S3 URL (full size)
  thumbnailUrl: string | null;      // S3 URL (thumbnail)
  source: PhotoSource;              // groups photos in gallery
  siteVisitId: string | null;       // set if sourced from a SiteVisit
  uploadedBy: string;               // User ID
  takenAt: Date | null;             // EXIF date if available, else upload date
  caption: string | null;
  deletedAt: Date | null;
}
```

**Photo gallery grouping:**
```
Project Photos — Smith Deck Job
  ├─ Site Visit (Feb 20)    [3 photos]   ← auto-attached when job won
  ├─ In Progress            [7 photos]   ← uploaded by field crew during tasks
  └─ Completion             [4 photos]   ← uploaded at project sign-off
```

**Migration from `projectImages` string:**
- Existing `projectImages` comma-separated URLs → create `ProjectPhoto` rows with `source: 'other'`
- New uploads go through `ProjectPhoto` table
- `projectImages` field on Project is deprecated but not removed until migration is complete

---

### `EmailConnection` (Supabase) — Renamed from `GmailConnection`

Multi-provider email connection for pipeline import. Supports Gmail and Microsoft 365 via provider abstraction layer. Stores OAuth tokens, sync profile (pattern detection rules), webhook subscription, and AI feature flags.

```typescript
interface EmailConnection {
  id: string;
  companyId: string;
  provider: 'gmail' | 'microsoft365';
  accessToken: string;              // encrypted at rest
  refreshToken: string;             // encrypted at rest
  tokenExpiresAt: Date;
  userEmail: string;
  userName: string;
  syncProfile: SyncProfile;         // pattern detection rules (JSONB)
  syncIntervalMinutes: number;
  lastSyncHistoryId: string | null;  // Gmail historyId or M365 deltaLink
  lastSyncAt: Date | null;
  opsLabelId: string | null;        // Gmail label ID or M365 category ID
  webhookSubscriptionId: string | null;
  webhookExpiresAt: Date | null;
  aiReviewEnabled: boolean;
  aiMemoryEnabled: boolean;
  status: 'active' | 'paused' | 'error' | 'setup_incomplete';
  createdAt: Date;
  updatedAt: Date;
}
```

**See [Email Pipeline Integration](#email-pipeline-integration) for full sync logic, pattern detection, AI classification, and webhook architecture.**

---

## Automation Rules & Triggers

### Automation A: Estimate Sent → Create Client

**Trigger:** User clicks "Send Estimate" and estimate has no `clientId`

**Flow:**
1. Inline prompt: "Who is this estimate for?"
2. User types name — auto-suggests existing `Client` records (fuzzy search by name + email)
3. User selects existing client OR confirms new
4. If new: `Client` created with `{ name: contactName, email: contactEmail, phone: contactPhone }` from linked Opportunity
5. `estimate.clientId = client.id`
6. `opportunity.clientId = client.id` (if opportunity linked)

**Rule:** This prompt is non-skippable. An estimate cannot be sent without a client.

---

### Automation B: Estimate Sent → Create/Link Project

**Trigger:** User clicks "Send Estimate" (after client step)

**Flow:**
1. Inline prompt: "File into a project?"
2. User searches existing projects for this client OR creates new
3. If new: `Project` created with `{ title: estimate.title, clientId, status: 'RFQ', opportunityId }`
4. `estimate.projectId = project.id`
5. `opportunity.projectId = project.id` (if opportunity linked)
6. `project.status → Estimated`

**Rule:** This prompt can be skipped — estimates can remain standalone. Filing into a project is required before task generation (prompted again at approval if still null).

---

### Automation C: Estimate Approved → Generate Tasks

**Trigger:** `estimate.status` changes to `Approved`

**Prerequisites:** `estimate.projectId` must be set. If null, prompt user to file into a project first.

**Flow:**
1. If `CompanySettings.autoGenerateTasks = false` (default): open Review Tasks modal
2. If `CompanySettings.autoGenerateTasks = true`: generate silently

**Task generation logic (per LABOR line item):**
```
For each lineItem WHERE lineItem.type = 'LABOR':
  If lineItem.taskTypeId is set:
    templates = TaskTemplate[] for that taskTypeId (ordered by displayOrder)
    If templates.length > 0:
      → Propose one task per template
        title: template.title
        crew: template.defaultTeamMemberIds OR taskType.defaultTeamMemberIds
    Else:
      → Propose one generic task
        title: lineItem.description
        crew: taskType.defaultTeamMemberIds
  Else:
    → Propose one generic task
      title: lineItem.description
      crew: []
```

**After confirmation:**
- `ProjectTask` created for each confirmed task
- `task.sourceLineItemId = lineItem.id`
- `task.sourceEstimateId = estimate.id`
- `task.status = 'Booked'`
- `opportunity.stage → won` (if not already)
- `project.status → Accepted`

---

### Automation D: Site Visit Completed → Opportunity Stage Advance

**Trigger:** `SiteVisit.status → completed`

**Flow:**
1. Auto-create Activity on Opportunity timeline (type: `site_visit`)
2. Prompt: "Ready to build an estimate?" (dismissible)
3. If Yes → open Estimate creation form pre-linked to this opportunity → `opportunity.stage → quoting`

---

### Automation E: Opportunity Won → Attach Site Visit Photos

**Trigger:** `opportunity.stage → won`

**Flow:**
```
For each SiteVisit WHERE siteVisit.opportunityId = opportunity.id:
  For each photo URL in siteVisit.photos:
    Create ProjectPhoto {
      projectId: opportunity.projectId,
      url: photo,
      source: 'site_visit',
      siteVisitId: siteVisit.id,
      uploadedBy: siteVisit.createdBy,
      takenAt: null
    }
```

---

### Automation F: Project Status Cascades

| Trigger | Effect |
|---|---|
| Estimate sent (project linked) | `project.status → Estimated` |
| Estimate approved | `project.status → Accepted` |
| First ProjectTask status → InProgress | `project.status → InProgress` |
| All ProjectTasks status = Completed | `project.status → Completed` (prompt) |
| Invoice status → Paid | `project.status → Closed` |

---

### Automation G: Auto Follow-Up on Quoted Stage

**Trigger:** `opportunity.stageEnteredAt` for `quoted` stage + `CompanySettings.followUpReminderDays` days have elapsed

**Implementation:** Scheduled cron job or Supabase Edge Function running every hour

**Flow:**
1. Query: opportunities WHERE stage = `quoted` AND stageEnteredAt < NOW - followUpReminderDays AND no FollowUp with type `quote_follow_up` in last X days
2. For each matching opportunity:
   - Create `FollowUp { type: 'quote_follow_up', isAutoGenerated: true, triggerSource: 'auto_follow_up_timer' }`
   - `opportunity.stage → follow_up`
   - `opportunity.nextFollowUpAt = followUp.dueAt`

---

## Communication Logging

### Manual Communication Logging

Staff can log any communication directly from the Opportunity or Project activity timeline:

**Log a Call:**
```
type: call
direction: inbound | outbound
subject: "Called John re: estimate"
content: call notes
outcome: "left voicemail" | "discussed" | "no answer"
durationMinutes: 5
```

**Log an Email:**
```
type: email
direction: inbound | outbound
subject: email subject line
content: email body / summary
attachments: [S3 URLs]
```

**Log a Meeting:**
```
type: meeting
subject: "Site meeting with John"
content: meeting notes
durationMinutes: 45
outcome: "agreed on scope"
```

**Log a Note:**
```
type: note
subject: optional
content: free-form notes
```

**Log a Text/SMS:**
```
type: note   (no dedicated SMS type in v1)
subject: "Text from John"
content: message content
direction: inbound | outbound
```

### Activity Comments

After any activity is logged, team members can append internal comments:

```
Activity: "Called John Smith — Left voicemail"    ● Yesterday 3:15pm
  [INTERNAL] Sarah: "He texted back, calling tomorrow"
  [INTERNAL] John:  "I'll take the call"
  [+ Add comment]
```

**Rules:**
- Comments are visible to all staff at the company
- Comments are never visible to clients (future portal: `isClientVisible` toggle)
- Comments are soft-deleted only

### Activity Timeline Display

Activities are shown in reverse chronological order on both:
- **Opportunity card** (all activities pre-win + win event)
- **Project detail** (all activities post-project-creation)

Timeline includes:
- Manual activities (calls, emails, meetings, notes)
- System events (estimate sent, estimate approved, stage changes, tasks created)
- Auto-logged Gmail emails
- Site visit completions (with photo count)
- Invoice events (sent, payment received)

---

## Site Visits

### Creating a Site Visit

Site visits can be created from:
1. **Opportunity card** → "Book Site Visit" button
2. **Calendar** → "New Event" → select type "Site Visit" → link to Opportunity/Project
3. **Project detail** → "Book Site Visit" (for post-win check-ins)

**Required fields:** scheduledAt, assigneeIds (at least one), opportunityId OR projectId

### On-Site Experience (Mobile)

When a site visit is due:
1. Staff receives calendar notification
2. Opens site visit from Calendar or Opportunity card
3. Taps "Start Visit" → status → `in_progress`
4. Captures photos (camera or gallery)
5. Fills notes and measurements
6. Taps "Complete Visit" → status → `completed`

### Site Visit Data Capture

```
Notes field:        "Existing deck is 14ft × 28ft (392sqft). 6 existing posts,
                     4 need replacement. Access tight on north side."

Internal Notes:     "Client wants work done before July 4 — firm deadline"

Measurements:       "Deck: 14ft × 28ft = 392sqft
                     Posts: 6 total, 30in above grade
                     Railing: 52 linear feet"

Photos:             [photo1.jpg] [photo2.jpg] [photo3.jpg]
```

### Site Visit → Estimate Continuity

When a user creates an estimate after completing a site visit:
- Site visit notes are shown as a reference panel in the estimate builder (read-only sidebar)
- Photos from the site visit are accessible for attaching to the estimate PDF
- Measurements can be copy-pasted into line item descriptions

---

## Project Photos

### Photo Sources

| Source | How Added | When Added |
|---|---|---|
| `site_visit` | Auto from SiteVisit.photos | When opportunity is won |
| `in_progress` | Uploaded by field crew during task work | During InProgress status |
| `completion` | Uploaded at project sign-off | When all tasks complete |
| `other` | Manual upload from project detail | Any time |

### Gallery UI

```
Project Photos — Smith Deck Job  [Upload Photo ▼]

  Site Visit  Feb 20                         [3]
  ┌────┐ ┌────┐ ┌────┐
  │    │ │    │ │    │
  └────┘ └────┘ └────┘

  In Progress                               [7]
  ┌────┐ ┌────┐ ┌────┐ ┌────┐
  │    │ │    │ │    │ │    │  +3
  └────┘ └────┘ └────┘ └────┘

  Completion                                [4]
  ┌────┐ ┌────┐ ┌────┐ ┌────┐
  │    │ │    │ │    │ │    │
  └────┘ └────┘ └────┘ └────┘
```

### Migration from Legacy `projectImages`

The `Project.projectImages` field (comma-separated string) is deprecated. Migration:
1. Read `projectImages` string, split by comma
2. For each URL: create `ProjectPhoto { source: 'other', url, projectId, companyId }`
3. Mark `projectImages` as empty string once migrated
4. Remove field from API usage after all records migrated

---

## Email Pipeline Integration

> **Platform status**: Email integration is implemented on OPS-Web with support for both Gmail and Microsoft 365. API routes under `/api/integrations/email/`, plus a provider abstraction layer, pattern detection engine, AI classification system, webhook-driven sync, and a 5-step "Import Your Pipeline" wizard. No email integration exists on iOS. The `email_connections` table (renamed from `gmail_connections`) stores per-connection provider, tokens, sync profile, webhook subscription, and AI feature flags.

### Provider Support

| Provider | Auth | Scopes | Incremental Sync | Push Notifications |
|----------|------|--------|-------------------|--------------------|
| Gmail | Google OAuth 2.0 | `gmail.readonly`, `gmail.modify`, `gmail.labels` | History API (`startHistoryId`) | Google Cloud Pub/Sub (`users.watch()`) |
| Microsoft 365 | Microsoft Identity Platform (MSAL) | `Mail.Read`, `Mail.ReadWrite` | Delta queries (`/me/messages/delta`) | Graph Change Notifications (`POST /subscriptions`) |

A single company can connect both providers (e.g., owner uses Gmail, office manager uses M365). Each connection is a separate `email_connections` row with its own sync profile, webhook subscription, and sync token. Client matching and duplicate detection operate across all connections for a company.

### OAuth Flow

```
Settings → Integrations → Email
  ├─ Connect Gmail → Google OAuth → email_connections (provider: gmail)
  └─ Connect Microsoft 365 → MSAL OAuth → email_connections (provider: microsoft365)
```

### Provider Abstraction Layer

All email operations go through a shared `EmailProvider` interface. Each provider (Gmail, M365) implements the interface, translating to provider-specific APIs internally.

```typescript
interface EmailProvider {
  readonly providerType: 'gmail' | 'microsoft365'

  // Auth
  connect(companyId: string): Promise<AuthResult>
  refreshToken(connectionId: string): Promise<void>

  // Incremental sync (Gmail: historyId, M365: deltaLink)
  fetchNewEmailsSince(syncToken: string): Promise<{ emails: Email[]; nextSyncToken: string }>
  fetchSentEmailsSince(syncToken: string): Promise<{ emails: Email[]; nextSyncToken: string }>

  // Search (for wizard Step 2 sent mail analysis)
  searchEmails(query: string, options?: { maxResults?: number; after?: Date }): Promise<Email[]>

  // Thread operations
  fetchThread(threadId: string): Promise<Email[]>

  // Labels/categories
  createLabel(name: string): Promise<string>
  applyLabel(threadId: string, labelId: string): Promise<void>
  removeLabel(threadId: string, labelId: string): Promise<void>
  listLabels(): Promise<Label[]>

  // Drafts (for AI auto-draft)
  createDraft(to: string, subject: string, body: string, threadId?: string): Promise<string>

  // Push notifications
  setupWebhook(webhookUrl: string): Promise<WebhookSubscription>
  renewWebhook(subscriptionId: string): Promise<void>
  validateWebhookRequest(request: Request): Promise<boolean>

  // Profile
  getProfile(): Promise<{ email: string; name: string }>
}
```

The `syncToken` parameter abstracts over Gmail's `historyId` and M365's `deltaLink` — each provider translates internally.

**Key provider differences:**

| Concept | Gmail | Microsoft 365 |
|---------|-------|---------------|
| Thread identifier | `threadId` | `conversationId` |
| Tagging mechanism | Labels (multiple per email) | Categories (color-coded tags) |
| Push notification renewal | Watch expires every 7 days, renew daily | Subscription expires every 3 days, renew every 2 days |
| Email body format | base64-encoded parts | `body.content` directly as HTML/text |
| "OPS Pipeline" tag | Gmail label | M365 category |

### Import Your Pipeline Wizard

A 5-step wizard replaces the previous 6-step filter-based wizard. Located in `src/components/settings/email-setup-wizard.tsx`.

**Steps:**

1. **Connect** — Two buttons: "Connect Gmail" / "Connect Microsoft 365". OAuth flow, auto-proceed on success.

2. **Analyze Your Inbox** — Automatic analysis (~30-60 seconds) with live progress indicator. Three parallel operations:
   - **Sent mail scan** — analyzes most common outbound subjects to non-company addresses to detect estimate/quote patterns
   - **Platform detection** — identifies known form senders (Wix, WordPress, Squarespace, Jotform, HubSpot) and bid platforms (Procore, SmartBidNet, BuilderTrend) in inbox
   - **AI classification** — classifies remaining personal emails not matching any pattern as lead/not-lead
   - Only analyzes threads with activity within last 3 months
   - Uses the `email_scan_jobs` table (renamed from `gmail_scan_jobs`) for async job tracking with progress
   - Error handling: partial results accepted if one operation fails; hard timeout at 120 seconds; resume from saved progress if browser closed mid-scan

3. **Confirm Your Sources** — Displays discovered sources grouped by type:
   - Detected estimate subject pattern with thread count (toggle on/off, editable)
   - Website form submissions with platform name and count (toggle on/off)
   - Bid invitations with platform name and count (toggle on/off)
   - Additional AI-identified inquiries (expandable for individual review)
   - Manual add for additional patterns/sources

4. **Review & Import** — All detected leads with AI-determined pipeline stage:
   - Grouped by stage: New Lead, Qualifying, Quoting, Quoted, Follow-Up, Negotiation, Won, Lost
   - Each lead shows: client name, email, last message date, correspondence count, detected stage
   - Duplicates pre-grouped with merge prompt
   - User can adjust stage, remove false positives, merge duplicates
   - "Import All" button with count

5. **Activate Sync** — Confirms "OPS Pipeline" label/category applied to imported leads:
   - Sync frequency selector: 15 min / 1 hour / 2 hours / 24 hours / Manual only
   - Note: real-time via push notifications, scheduled sync as safety net
   - Summary card: leads imported, sync frequency, next sync time

**Wizard state is persisted** on the `email_connections` record via the `sync_filters` JSONB column (mapped as `syncFilters` in TypeScript) and `status` column (`setup_incomplete` during wizard). Note: The DB column retains the name `sync_filters` for backward compatibility — the TypeScript type is `SyncProfile`.

### Pattern Detection Engine

Runs during wizard Step 2. Produces the **sync profile** — the ruleset used by every ongoing sync cycle. Stored as JSONB on the `email_connections.sync_filters` column (TypeScript field: `syncFilters: SyncProfile`).

**2A: Sent Mail Analysis**
1. Fetch sent messages (last 3 months, skip internal company domain addresses)
2. Group by subject line (normalized — strip "Re:", "Fwd:", whitespace)
3. Rank by frequency — the most common subject sent to unique external recipients is the estimate pattern
4. Present to user for confirmation in Step 3
5. User can edit the pattern or add additional patterns (some businesses have multiple — residential vs commercial)

**2B: Known Platform Detection**

Registry of known form notification senders and bid platforms:

| Category | Detected By | Examples |
|----------|-------------|---------|
| Website forms | Sender domain | `notifications@wix-forms.com`, `*@wordpress.com`, `*@squarespace.com`, `*@jotform.com`, `*@typeform.com` |
| Bid platforms | Sender domain | `*@smartbidnet.com`, `*@procore.com`, `*@buildertrend.com`, `*@plangrid.com`, `*@buildingconnected.com` |
| CRM/lead gen | Sender domain | `*@hubspot.com`, `*@salesforce.com`, `*@thumbtack.com`, `*@homeadvisor.com`, `*@houzz.com` |
| Google reviews | Sender address | `businessprofile-noreply@google.com` |
| Forwarded forms | Pattern | Subject contains "got a new submission", "new form entry", "new contact form" + forwarded by known team member |

**2C: Forwarded Lead Detection**

Many trades businesses have an office manager or partner who forwards leads. Detected via: emails where sender is from user's own company domain, subject contains forwarding indicators ("Fwd:", "got a new submission"), body contains a nested forwarded message from a form platform.

**2D: Business Domain Identification**

From sent mail analysis, identify user's company domain(s): domains the user sends from, domains appearing frequently in CC/To on business threads. User confirms in Step 3. Used to exclude internal correspondence and identify the "forwarder" pattern.

**2E: Sync Profile Output**

```json
{
  "estimateSubjectPatterns": ["Canpro Deck and Rail Estimate"],
  "companyDomains": ["canprodeckandrail.com"],
  "teamForwarders": ["jared@canprodeckandrail.com", "victoria@canprodeckandrail.com"],
  "knownPlatformSenders": ["notifications@wix-forms.com", "notifications@com2.smartbidnet.com"],
  "formSubjectPatterns": ["got a new submission", "new form entry"],
  "userEmailAddresses": ["canprojack@gmail.com"],
  "aiClassificationThreshold": 0.7
}
```

`syncIntervalMinutes`, `aiReviewEnabled`, `aiMemoryEnabled`, `lastSyncHistoryId` are stored as top-level columns on `email_connections`, not in the sync profile JSONB. The sync profile contains only pattern/source detection rules. The `aiClassificationThreshold` is configurable per connection (default 0.7).

### AI Classification System

Two modes: **Initial Scan** (during wizard) and **Ongoing Review** (feature-gated via `ai_email_review`).

**3A: Initial Scan — Bulk Classification**

After pattern detection, remaining unmatched emails in `CATEGORY_PERSONAL` go to AI. Skip `CATEGORY_PROMOTIONS`, `CATEGORY_UPDATES`, `CATEGORY_SOCIAL`, `CATEGORY_FORUMS` entirely.

AI validates ALL candidates — even pattern-matched leads go through AI confirmation to:
- Confirm it's actually a lead
- Extract structured data: client name, phone, project description, estimated scope
- Assign pipeline stage
- Detect duplicates across threads

**Output per lead (~50 tokens):**

```json
{
  "id": "abc123",
  "v": "lead",
  "c": 0.95,
  "stage": "quoted",
  "val": 4500,
  "client": {
    "name": "John Knechtel",
    "email": "knechtel.john@gmail.com",
    "phone": null,
    "desc": "Deck railing replacement, 2 decks, glass and picket options"
  },
  "dupes": ["def456", "ghi789"]
}
```

- `v`: verdict — `"lead"`, `"biz"` (subtrade/vendor), `"skip"` (noise)
- `c`: confidence 0-1
- `dupes`: other email IDs AI believes belong to same client/project
- Emails classified as `"lead"` with confidence >= 0.7 imported. Below 0.7 queued for user review in Step 4.

**3B: Thread Analysis — Stage Placement**

For every confirmed lead thread with activity within 3 months, full thread content sent to AI for accurate stage placement. Batching: 5-10 threads per API call to amortize system prompt cost.

**3C: Ongoing AI Review (Feature-Gated)**

When `ai_email_review` is enabled (requires both product-level feature flag AND admin override), every sync cycle includes:

1. **New email classification** — unmatched emails go through AI classification
2. **Stage re-evaluation** — for active leads with new emails, AI reviews thread context and determines stage advancement
3. **Win/loss detection** — AI flags threads where client appears to have confirmed or declined

**3D: Terminal Stage Detection Rules**

AI never auto-advances to `won` or `lost`. Instead:

- Win language detected ("let's go ahead", "we'd like to proceed") → notification: "{Client} may have accepted your estimate. [Review → Won?]"
- Loss language detected ("went with another company", "too expensive") → notification: "{Client} may have declined. [Review → Lost?]"

User clicks through to existing Won/Lost confirmation dialogs.

### 5-Tier Client Matching

**Service:** `src/lib/api/services/email-matching-service.ts`

When emails are imported or synced, each is matched against existing clients via a 5-tier cascade:

| Tier | Strategy | Confidence | Auto-link? |
|------|----------|------------|------------|
| 1 | Exact email match (client or sub-client email) | `exact` | Yes |
| 2 | Domain match (non-public domain, single client) | `domain` | Yes — add as sub-contact |
| 2b | Domain match (multiple clients share domain) | `domain` | No — `needsReview: true` |
| 3 | Name match (AI-extracted name matches existing client last name) | `name` | No — `needsReview: true` |
| 4 | Thread CC association (email CC'd on thread linked to existing client) | `thread` | Yes — add as sub-contact |
| 5 | AI duplicate detection (feature-gated: signatures, phone, addresses in body) | `ai` | No — `needsReview: true` |

**Resolution rules:**
- Exact email match → log activity on existing client
- Domain match (single) → create sub-contact, log activity
- Domain match (multiple) → queue for user review
- Name match → queue for user review
- Thread CC association → create sub-contact, log activity
- AI duplicate detection → queue for user review
- No match at any tier → create new client + opportunity

**Public domains** (gmail.com, yahoo.com, outlook.com, shaw.ca, telus.net, icloud.com, protonmail.com, live.com, comcast.net, att.net, verizon.net, msn.com, me.com, mac.com, ymail.com, mail.com, zoho.com, gmx.com, inbox.com, etc.) are excluded from domain matching. Defined in `PUBLIC_EMAIL_DOMAINS` in `src/lib/types/pipeline.ts`.

### Sync Engine

**4A: Sync Triggers (all four built day one)**

| Trigger | Implementation | Latency |
|---------|---------------|---------|
| **Scheduled** | Cron checks interval (15min/1hr/2hr/24hr) | Up to interval |
| **Manual** | "Sync Now" button | Immediate |
| **Gmail Push** | Google Cloud Pub/Sub → `users.watch()` → webhook endpoint | ~seconds |
| **M365 Push** | Microsoft Graph Change Notifications → subscription on `/me/messages` → webhook endpoint | ~seconds |

**4B: Webhook Architecture**

**Gmail:**
1. On connection setup, call `gmail.users.watch()` with Pub/Sub topic
2. Google publishes to Pub/Sub topic on inbox/sent changes
3. Pub/Sub pushes to: `POST /api/integrations/email/webhook/gmail`
4. Validate, deduplicate, queue sync job, return 200 immediately
5. Watch expires every 7 days — cron renews daily

**Microsoft 365:**
1. On connection setup, create subscription: `POST /subscriptions` on `me/messages`
2. M365 sends change notifications to: `POST /api/integrations/email/webhook/microsoft365`
3. Validate subscription (M365 requires validation handshake), queue sync job, return 200
4. Subscription expires every 3 days — cron renews every 2 days

**Shared webhook endpoint logic:**
1. Validate request authenticity (Pub/Sub signature / M365 validation token)
2. Extract connection ID
3. Debounce — if sync ran for this connection in last 30 seconds, skip
4. Queue sync job (don't run inline)
5. Return 200 immediately

**4C: Sync Cycle — Full Flow**

```
1. Fetch new emails since lastSyncHistoryId
   ├── Inbox (inbound)
   └── Sent (outbound)

2. Pattern matching (fast, free)
   ├── Sender matches known platform? → candidate
   ├── Sender matches team forwarder? → candidate
   ├── Subject matches form submission pattern? → candidate
   ├── Reply in existing OPS lead thread? → auto-link
   └── User sent to new external address with estimate pattern? → new lead

3. Sent folder safety net
   ├── User replied to address not in OPS? → new lead
   ├── User replied in thread already in OPS? → update activity
   └── User sent to known client? → log outbound activity

4. Thread inheritance
   └── Any email in thread linked to OPS client → auto-link, log activity

5. AI classification (feature-gated — skip if disabled)
   └── Remaining unmatched personal emails → AI classify

6. Stage evaluation
   ├── Free tier: correspondence count rules
   │   ├── 0 outbound → new_lead
   │   ├── 1 outbound → qualifying
   │   ├── 2+ exchanges → quoting
   │   └── Stale threshold exceeded → follow_up
   └── AI tier (feature-gated): AI reviews thread context

7. Client matching & sub-contact resolution (5-tier cascade)

8. Apply labels
   └── New lead/activity → apply "OPS Pipeline" label/category

9. Create/update OPS records
   ├── New lead → create Client + Opportunity + Activity
   ├── Existing lead, new email → create Activity, update stage
   └── Duplicate detection → flag for user review

10. AI memory update (feature-gated — see AI Memory System)

11. Notifications
    ├── "3 new emails synced — 1 new lead from john@example.com"
    ├── Win/loss flags
    └── Duplicate flags

12. Update lastSyncHistoryId
```

### Smart Pipeline Staging

**5A: Free Tier — Correspondence Count Rules**

| Thread State | Stage | Detection |
|---|---|---|
| Inbound only, 0 outbound | `new_lead` | outbound_count = 0 |
| User sent 1 reply | `qualifying` | outbound_count = 1, total < 4 |
| 2+ outbound, 4+ total messages | `quoting` | outbound_count >= 2, total >= 4 |
| 3+ outbound, 6+ total messages | `quoted` | outbound_count >= 3, total >= 6 |
| Last message outbound, no reply for X days | `follow_up` | last_message_direction = out, age > autoFollowUpDays (applies at any active stage) |
| Client replied after quiet period | `negotiation` | previous stage was follow_up, new inbound arrived |

**Limitation:** Correspondence-count rules cannot reliably distinguish "discussing scope" from "estimate was sent." They place leads in roughly the right area of the pipeline. Users can always drag to correct on the Kanban board. The AI tier handles this accurately by detecting actual pricing in outbound messages.

**5B: AI Tier — Context-Aware Staging (Feature-Gated)**

AI reads thread content and detects:

| Signal | Stage |
|---|---|
| User asked for photos/measurements | `qualifying` |
| User sent pricing/dollar amounts | `quoted` |
| User mentioned promotion/discount | `quoted` |
| Client comparing quotes | `negotiation` |
| Client discussing scheduling/timing | `negotiation` |
| Client accepted | Flag → `won` prompt |
| Client declined | Flag → `lost` prompt |
| Client silent > 30 days, last was outbound | Flag → possible `lost` |

**AI output per thread (~20 tokens):**

```json
{
  "stage": "quoted",
  "c": 0.9,
  "val": 4500,
  "signals": ["pricing_sent", "promo_mentioned"],
  "terminal_flag": null
}
```

**5C: Correspondence Tracking on Opportunity**

Email threads are linked to opportunities via the `opportunity_email_threads` junction table (not a column on opportunities). This enables fast O(1) sync lookup via a unique index on `thread_id`. See `03_DATA_ARCHITECTURE.md` for the full schema.

Additional columns on `opportunities` for correspondence tracking:

```
correspondence_count: INT DEFAULT 0
outbound_count: INT DEFAULT 0
inbound_count: INT DEFAULT 0
last_inbound_at: TIMESTAMPTZ
last_outbound_at: TIMESTAMPTZ
last_message_direction: TEXT ("in" | "out")
ai_stage_confidence: FLOAT
ai_stage_signals: TEXT[]
detected_value: INT
```

### AI Memory System (Feature-Gated)

Hybrid vector (pgvector) + knowledge graph (Postgres) + Mem0 orchestration. Builds a "company brain" that learns the user's business patterns over time. Gated behind the `ai_email_memory` feature flag (requires both product-level flag AND admin override).

**Three Storage Layers:**

| Layer | Purpose | Storage |
|---|---|---|
| `agent_memories` | Facts, preferences, traits extracted from emails | Postgres + pgvector `halfvec(1536)` embeddings |
| `agent_knowledge_graph` | Entity relationships with temporal validity | Postgres relational edges (subject → predicate → object) |
| `agent_writing_profiles` | Communication style per user | Structured Postgres table |

**Memory Dimensions:**

| Dimension | What It Captures | Source |
|---|---|---|
| Communication Style | Tone, formality, greetings, sign-offs, response length | Sent emails |
| Quoting Patterns | Pricing structure, estimate presentation, discount framing | Outbound estimate emails |
| Sales Methodology | Response speed, info requested first, objection handling, follow-up cadence | Full thread analysis |
| Business Knowledge | Services, service area, materials, limitations, promotions, subtrades | All outbound correspondence |
| Client Handling | Price objection responses, lost deal handling, upselling, referrals | Thread outcomes mapped to correspondence |

**Email Sync → Memory Pipeline:**

On every AI-tier sync cycle, for each outbound email:

```
Extract entities → knowledge graph
  ├── People (names, emails, phones)
  ├── Companies
  ├── Services discussed
  ├── Pricing mentioned
  └── Relationships

Extract facts → agent_memories + pgvector
  ├── "User charges $65-85/LF for aluminum picket railing"
  ├── "User cannot do glass on stairs"
  └── "User services Salt Spring Island frequently"

Update writing profile → agent_writing_profiles
  ├── Greeting patterns
  ├── Sign-off patterns
  ├── Tone markers
  └── Response structure

Embed email content → pgvector
  └── Semantic embedding for future retrieval
```

Key principle: don't store emails verbatim. Extract knowledge, embed for semantic search, discard raw text. Memory consolidation runs periodically to merge redundant entries and prune stale facts.

**Memory-Powered Draft Generation:**

When user clicks "Draft Reply" or auto-draft triggers:

1. Semantic search pgvector for past emails to similar clients about similar projects
2. Graph traversal for client's history, related entities, outstanding quotes
3. Retrieve writing profile — tone, greeting, sign-off, response length
4. Retrieve relevant facts — current promotions, pricing, limitations
5. LLM generates draft in user's exact voice with accurate business details

**Confidence & Progressive Unlock:**

| Emails Analyzed | Confidence | Capabilities |
|---|---|---|
| 0-25 | 0.0-0.2 | Learning only |
| 25-100 | 0.2-0.5 | Analytics dashboard ("your avg response time: 2.3 hours") |
| 100-250 | 0.5-0.75 | "Draft Reply" button available |
| 250+ | 0.75-1.0 | Auto-draft to inbox (saved as draft, never sent without user action) |

**Memory Feedback Loop:**

Each correction creates a new `agent_memories` entry with `memory_type = 'correction'` and a reference to the original memory/action being corrected. Mem0's consolidation merges corrections into the base facts over time. User edits to drafts, stage overrides, rejected client matches, and manually created leads all feed back into the memory system.

### Feature Gate Architecture

**Free vs Gated:**

| Feature | Free (All Users) | AI-Powered (Gated) |
|---|---|---|
| Pattern detection & sync profile | Yes | Yes |
| Sent folder safety net | Yes | Yes |
| Thread inheritance | Yes | Yes |
| Label application (mandatory) | Yes | Yes |
| Webhook push sync (Gmail + M365) | Yes | Yes |
| Initial AI classification during wizard | Yes | Yes |
| Initial AI stage placement (one-time) | Yes | Yes |
| Correspondence-count stage rules | Yes | Yes |
| Stale/follow-up time-based rules | Yes | Yes |
| Ongoing AI classification per sync | No | `ai_email_review` |
| Ongoing AI stage evaluation per sync | No | `ai_email_review` |
| Win/loss detection notifications | No | `ai_email_review` |
| AI duplicate detection | No | `ai_email_review` |
| Memory accumulation | No | `ai_email_memory` |
| Draft reply suggestions (confidence >= 0.5) | No | `ai_email_memory` |
| Auto-draft to inbox (confidence >= 0.75) | No | `ai_email_memory` |

The `ai_email_review` and `ai_email_memory` flags integrate into the existing feature flag system (`feature-flag-definitions.ts`, `feature-flags-store.ts`) but also require per-company OPS admin override via the `admin_feature_overrides` table. See `07_SPECIALIZED_FEATURES.md` §17 for full feature gate documentation.

**Code-level gate check:**

```typescript
async function isAIFeatureEnabled(
  companyId: string,
  feature: 'ai_email_review' | 'ai_email_memory'
): Promise<boolean> {
  const productEnabled = await canAccessFeature(feature)  // existing feature flag system
  const adminEnabled = await checkAdminOverride(companyId, feature)  // admin_feature_overrides table
  return productEnabled && adminEnabled
}
```

### Permissions

New permission module for the email integration, registered in the existing permission system (`permissions.ts`):

| Permission | Scopes | Description |
|---|---|---|
| `email.connect` | `["all"]` | Connect/disconnect email accounts |
| `email.view` | `["all", "own"]` | View imported leads and email activities |
| `email.manage` | `["all"]` | Run wizard, edit sync profile, manual sync |
| `email.configure_ai` | `["all"]` | Toggle AI features (requires admin override to be enabled) |

### Thread Grouping

Emails with the same `emailThreadId` (Gmail `threadId` or M365 `conversationId`) are grouped visually in the Activity timeline:

```
Email thread with John Smith — Deck Estimate          3 days ago
   (4 messages)  [expand]
   - You: "Hi John, your estimate is attached"        3 days ago
   - John: "Thanks, looks good. One question..."      2 days ago
   - You: "Happy to clarify — the membrane..."        2 days ago
   - John: "Perfect, let's proceed"                   Yesterday
```

### Service & Hook Inventory

**Services** (`src/lib/api/services/`):
| Service | File | Purpose |
|---------|------|---------|
| EmailService | `email-service.ts` | Provider abstraction, connection CRUD, OAuth tokens, message fetch |
| EmailMatchingService | `email-matching-service.ts` | 5-tier client matching cascade |
| EmailClassifier | `email-classifier.ts` | AI email classification and stage placement |
| EmailSyncService | `email-sync-service.ts` | Sync cycle orchestration, pattern matching, webhook handling |

**Hooks** (`src/lib/hooks/`):
| Hook | File | Purpose |
|------|------|---------|
| useEmailConnections | `use-email-connections.ts` | TanStack Query: fetch, update, delete connections |
| useEmailImport | `use-email-import.ts` | Start import, poll progress, Action Prompt UX |
| useEmailSyncNotifications | `use-email-sync-notifications.ts` | Real-time sync event notifications |

**Components:**
| Component | File | Purpose |
|-----------|------|---------|
| EmailSetupWizard | `settings/email-setup-wizard.tsx` | 5-step wizard (Connect → Activate Sync) |
| SourceConfirmPanel | `settings/source-confirm-panel.tsx` | Detected source review and toggle UI |
| ImportReviewPanel | `settings/import-review-panel.tsx` | Lead review, stage assignment, duplicate merge UI |

### Data Types

**EmailConnection:**
```typescript
interface EmailConnection {
  id: string;
  companyId: string;
  provider: 'gmail' | 'microsoft365';
  accessToken: string;
  refreshToken: string;
  tokenExpiresAt: Date;
  userEmail: string;
  userName: string;
  syncProfile: SyncProfile;
  syncIntervalMinutes: number;
  lastSyncHistoryId: string | null;
  lastSyncAt: Date | null;
  opsLabelId: string | null;
  webhookSubscriptionId: string | null;
  webhookExpiresAt: Date | null;
  aiReviewEnabled: boolean;
  aiMemoryEnabled: boolean;
  status: 'active' | 'paused' | 'error' | 'setup_incomplete';
  createdAt: Date;
  updatedAt: Date;
}
```

**SyncProfile:**
```typescript
interface SyncProfile {
  estimateSubjectPatterns: string[];
  companyDomains: string[];
  teamForwarders: string[];
  knownPlatformSenders: string[];
  formSubjectPatterns: string[];
  userEmailAddresses: string[];
  aiClassificationThreshold: number;
}
```

### Lead Auto-Creation Logic

When a lead is created from email import:
- `opportunity.source = 'email'`
- `opportunity.stage` = AI-determined or correspondence-count-determined stage
- `opportunity.winProbability` = based on stage
- `opportunity.tags = ['email-import']`
- Existing open opportunities are checked first — no duplicates created
- Correspondence tracking columns populated: `correspondence_count`, `outbound_count`, `inbound_count`, `last_inbound_at`, `last_outbound_at`, `last_message_direction`

---

## Entity Relationship Map

```
EmailConnection ────── Company ──── CompanySettings
                           │
          ┌────────────────┼────────────────┐
          │                │                │
       Client           Project          TaskType
          │            (folder)              │
          │          /    │    \        TaskTemplate[]
    SubClient[]   Est.  Est.  Est.  ←── (default tasks)
                   │     │     │
              LineItem[]  (LABOR → taskTypeId)
                   │
              ProjectTask[] ←── sourceLineItemId
                   │
              (startDate / endDate on task)
                   │
              (schedule)

   Opportunity ──────────────────────────── Project
   (pipeline card)  opportunityId              │
          │                                ProjectPhoto[]
          │                                 (source tagged)
     Activity[]
          │
     ActivityComment[]
          │
     SiteVisit[] ──── (dates stored directly; CalendarEvent removed)
          │
          └── photos[] ──► ProjectPhoto[]
                           (on job win)

   FollowUp[] ─── Opportunity
   StageTransition[] ─── Opportunity
   OpportunityEmailThread[] ─── Opportunity (junction: thread_id ↔ opportunity)

   Invoice ──── Project
      │    └─── Estimate (estimateId)
   Payment[]

   AdminFeatureOverride ─── Company (per-company AI feature gates)

   AgentMemory[] ─── Company (pgvector embeddings, feature-gated)
   AgentKnowledgeGraph[] ─── Company (entity relationship edges)
   AgentWritingProfile ─── Company + User (communication style)
```

---

## Status & Stage Reference

### Opportunity Stages (Pipeline)

| Stage | Slug | Trigger In | Trigger Out |
|---|---|---|---|
| New Lead | `new_lead` | Lead created | First activity logged |
| Qualifying | `qualifying` | Auto | Estimate created |
| Quoting | `quoting` | Estimate created | Estimate sent |
| Quoted | `quoted` | Estimate sent | X days elapsed → Follow Up; client replies → Negotiation |
| Follow Up | `follow_up` | Auto (X days) | Client replies → Negotiation |
| Negotiation | `negotiation` | Inbound activity | Revised estimate sent → Quoted; estimate approved → Won |
| Won | `won` | Estimate approved | Terminal |
| Lost | `lost` | Estimate declined | Terminal |

### Project Statuses

| Status | Meaning | Set When |
|---|---|---|
| `RFQ` | Request for Quote — project stub created, no estimate yet | Project auto-created at estimate send |
| `Estimated` | At least one estimate has been sent | Estimate sent |
| `Accepted` | Estimate approved, work authorized | Estimate approved |
| `InProgress` | Field work started | First task goes InProgress |
| `Completed` | All tasks done, ready to invoice | All tasks Completed |
| `Closed` | Invoice fully paid | Invoice status → Paid |
| `Archived` | Manually archived | Manual action |

### Estimate Statuses

| Status | Meaning |
|---|---|
| `draft` | Being built, not sent |
| `sent` | Sent to client |
| `viewed` | Client opened (if tracked) |
| `approved` | Client accepted |
| `changes_requested` | Client replied with change requests |
| `declined` | Client rejected |
| `converted` | Converted to invoice |
| `expired` | Past expiration date without response |
| `superseded` | Replaced by a newer version |

### Invoice Statuses

| Status | Meaning |
|---|---|
| `draft` | Being prepared |
| `sent` | Sent to client |
| `awaiting_payment` | Client acknowledged, payment pending |
| `partially_paid` | Deposit or progress payment received |
| `past_due` | Past due date, unpaid |
| `paid` | Fully paid — triggers project → Closed |
| `void` | Voided |
| `written_off` | Bad debt, written off |

### SiteVisit Statuses

| Status | Meaning |
|---|---|
| `scheduled` | Booked, upcoming |
| `in_progress` | Staff has arrived, capturing notes/photos |
| `completed` | Visit done, notes and photos saved |
| `cancelled` | Cancelled before completion |

---

## Implementation Notes

### Database Locations

| Entity | Backend | Notes |
|---|---|---|
| `TaskTemplate` | Bubble.io | Same backend as TaskType — same query patterns |
| `ActivityComment` | Supabase | Joins to Activity via `activityId` |
| `SiteVisit` | Supabase | Joins to Opportunity and Project |
| `ProjectPhoto` | Supabase | Replaces Bubble `projectImages` string |
| `EmailConnection` | Supabase | OAuth tokens (encrypted at rest), sync profile, webhook subscription, AI flags. Renamed from `gmail_connections`. |
| `CompanySettings` | Supabase | 1:1 with companyId |

### New Bubble API Endpoints Needed

```
GET  /obj/tasktemplate?constraints=[{"key":"companyId","constraint_type":"equals","value":X}]
POST /obj/tasktemplate
PATCH /obj/tasktemplate/:id
DELETE /obj/tasktemplate/:id

PATCH /obj/tasktype/:id          (add defaultTeamMemberIds field)
PATCH /obj/projecttask/:id       (add sourceLineItemId, sourceEstimateId fields)
PATCH /obj/project/:id           (add opportunityId field)
PATCH /obj/calendarevent/:id     (add eventType, opportunityId, siteVisitId fields)
```

### New Supabase Tables Needed

```sql
-- activity_comments
-- site_visits
-- project_photos
-- email_connections (renamed from gmail_connections)
-- opportunity_email_threads
-- admin_feature_overrides
-- agent_memories (feature-gated)
-- agent_knowledge_graph (feature-gated)
-- agent_writing_profiles (feature-gated)
-- company_settings (or alter existing if table exists)

-- Alter existing tables:
ALTER TABLE line_items ADD COLUMN type text DEFAULT 'LABOR';
ALTER TABLE line_items ADD COLUMN task_type_id text;
ALTER TABLE line_items ADD COLUMN estimated_hours numeric;

ALTER TABLE estimates ADD COLUMN project_id text;

ALTER TABLE invoices ADD COLUMN project_id text;
ALTER TABLE invoices ADD COLUMN estimate_id uuid REFERENCES estimates(id);

ALTER TABLE products ADD COLUMN type text DEFAULT 'LABOR';
ALTER TABLE products ADD COLUMN task_type_id text;

ALTER TABLE opportunities ADD COLUMN source_email_id text;

ALTER TABLE activities ADD COLUMN attachments text[] DEFAULT '{}';
ALTER TABLE activities ADD COLUMN email_thread_id text;
ALTER TABLE activities ADD COLUMN email_message_id text;
ALTER TABLE activities ADD COLUMN is_read boolean DEFAULT true;
ALTER TABLE activities ADD COLUMN site_visit_id uuid REFERENCES site_visits(id);
ALTER TABLE activities ADD COLUMN project_id text;
```

### Implementation Priority Order

**Phase 1 — Data layer (no UI changes yet):**
1. Add new Bubble fields: `TaskType.defaultTeamMemberIds`, `Project.opportunityId`, `ProjectTask` source fields (CalendarEvent has been removed — scheduling dates are on ProjectTask directly)
2. Create Bubble `TaskTemplate` data type
3. Supabase: alter `line_items`, `estimates`, `invoices`, `products`, `opportunities`, `activities`
4. Supabase: create `activity_comments`, `site_visits`, `project_photos`, `email_connections`, `opportunity_email_threads`, `admin_feature_overrides`, `agent_memories`, `agent_knowledge_graph`, `agent_writing_profiles`, `company_settings`

**Phase 2 — Automation (backend services):**
5. Estimate send flow: client creation + project creation inline prompts
6. Estimate approval: task generation logic + Review Tasks modal
7. Project status cascades
8. Auto follow-up timer (cron/edge function)

**Phase 3 — New features UI:**
9. Site visit create/edit/complete flow
10. Activity comments on timeline
11. Review Tasks modal
12. Project photo gallery (grouped by source)
13. TaskType settings: default crew + task templates

**Phase 4 — Email Pipeline Integration:**
14. Email OAuth connection flow (Gmail + M365, Settings → Integrations)
15. Pattern detection engine + "Import Your Pipeline" wizard
16. Webhook-driven sync engine with provider abstraction
17. 5-tier client matching + correspondence tracking
18. AI classification and stage placement (feature-gated)
19. AI memory system (feature-gated)

### Implementation Status by Platform (as of February 2026)

#### Pipeline — iOS Views (Built)

The Pipeline tab is fully implemented on iOS with the following views in `OPS/OPS/Views/Pipeline/`:

| File | Purpose |
|---|---|
| `PipelineTabView.swift` | Top-level tab container |
| `PipelineView.swift` | Main Kanban board view |
| `PipelineStageStrip.swift` | Horizontal stage selector strip |
| `PipelinePlaceholderView.swift` | Empty state placeholder |
| `OpportunityCard.swift` | Pipeline card for a single opportunity |
| `OpportunityDetailView.swift` | Full detail view for an opportunity |
| `OpportunityFormSheet.swift` | Create/edit opportunity form |
| `OpportunityBadgeView.swift` | Stage/status badge component |
| `ActivityFormSheet.swift` | Log activity from opportunity |
| `ActivityRowView.swift` | Single activity row in timeline |
| `FollowUpRowView.swift` | Follow-up reminder row |
| `MarkLostSheet.swift` | Mark opportunity as lost (with reason prompt) |

#### Estimates — iOS Views (Built)

Estimates are fully implemented on iOS with the following views in `OPS/OPS/Views/Estimates/`:

| File | Purpose |
|---|---|
| `EstimatesListView.swift` | List of estimates (filterable) |
| `EstimateDetailView.swift` | Full estimate detail view |
| `EstimateFormSheet.swift` | Create/edit estimate |
| `EstimateCard.swift` | Summary card for estimate lists |
| `LineItemEditSheet.swift` | Add/edit individual line items |
| `ProductPickerSheet.swift` | Pick from product catalog when adding line items |

#### Invoices — iOS Views (Built)

Invoices are fully implemented on iOS with the following views in `OPS/OPS/Views/Invoices/`:

| File | Purpose |
|---|---|
| `InvoicesListView.swift` | List of invoices (filterable) |
| `InvoiceDetailView.swift` | Full invoice detail view |
| `InvoiceCard.swift` | Summary card for invoice lists |
| `PaymentRecordSheet.swift` | Record a payment against an invoice |

#### SiteVisit — Model Only (No iOS Views)

The `SiteVisit` data model exists at `OPS/OPS/DataModels/Supabase/SiteVisit.swift` (SwiftData `@Model` with fields: `id`, `opportunityId`, `companyId`, `status`, `scheduledAt`, `completedAt`, `notes`, `address`, `assignedTo`, `createdAt`). However, no dedicated iOS views exist for site visits yet. Site visit UI (create, on-site capture, complete) is not yet built on iOS.

#### Email Pipeline Integration — Web Only (No iOS Implementation)

Email integration API routes exist on the web backend (`OPS-Web/src/app/api/integrations/email/`):
- `route.ts` — main email integration endpoint
- `callback/route.ts` — OAuth callback handler (Gmail + M365)
- `sync/route.ts` — sync trigger
- `webhook/gmail/route.ts` — Gmail Pub/Sub webhook receiver
- `webhook/microsoft365/route.ts` — M365 Change Notifications webhook receiver

Supporting web services: `email-service.ts`, `email-sync-service.ts`, `email-matching-service.ts`, `email-classifier.ts`, `use-email-connections.ts`, `email-setup-wizard.tsx`.

No email integration exists on iOS. The iOS app reads from the same `opportunities` table (which gains new correspondence tracking columns) but does not connect to or sync email accounts.

---

*This document supersedes any prior informal notes about entity relationships. All implementation decisions should reference this document.*
