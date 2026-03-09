# 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md

**OPS Software Bible — Complete Job Lifecycle: Inquiry → Close**

**Purpose**: Defines the complete data flow for a trade job from first contact through to a paid invoice. Documents all entity relationships, automation triggers, new entities, and required changes to existing entities. This is the master reference for how leads, pipeline, clients, estimates, projects, tasks, and invoices inter-operate.

**Last Updated**: February 28, 2026
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
10. [Gmail Integration](#gmail-integration)
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

### `GmailConnection` (Supabase) — NEW

OAuth connection for Gmail auto-logging. Supports both a company-level inbox and per-user individual accounts.

```typescript
type GmailConnectionType = 'company' | 'individual'

interface GmailConnection {
  id: string;
  companyId: string;
  type: GmailConnectionType;
  userId: string | null;            // null for company inbox connections
  email: string;                    // the Gmail address connected
  accessToken: string;              // encrypted at rest
  refreshToken: string;             // encrypted at rest
  expiresAt: Date;
  historyId: string | null;         // Gmail API: last synced history ID (incremental sync)
  syncEnabled: boolean;
  lastSyncedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}
```

**See [Gmail Integration](#gmail-integration) for full sync logic.**

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

## Gmail Integration

> **Platform status**: Gmail integration API routes exist on OPS-Web (`/api/integrations/gmail/`, `gmail-service.ts`, `use-gmail-connections.ts`). No Gmail integration exists on iOS — there are no Gmail-related Swift files in the iOS codebase.

### Connection Architecture

Two tiers of Gmail connection:
1. **Company inbox** (`type: 'company'`) — one shared inbox (e.g., info@company.com)
2. **Individual accounts** (`type: 'individual'`) — per-user Gmail (e.g., john@company.com)

Both connection types use the same `GmailConnection` table and OAuth flow.

### OAuth Flow

Uses Google OAuth 2.0 with Gmail read scope (`gmail.readonly`) plus optionally send scope (`gmail.send`):

```
Settings → Integrations → Gmail
  ├─ Company Inbox: [Connect Gmail] → OAuth → GmailConnection (type: company)
  └─ My Gmail: [Connect My Gmail] → OAuth → GmailConnection (type: individual, userId: me)
```

### Incremental Sync Logic

Gmail API `history.list` is used for incremental sync (not full mailbox scan):

```
1. Initial sync: fetch last 90 days of messages matching known client emails
2. Subsequent syncs: fetch history since GmailConnection.historyId
3. For each new message:
   a. Extract sender + recipient email addresses
   b. Match against Client.email in database
   c. If match found:
      → Find open Opportunity for that Client
      → Check: does Activity with emailMessageId already exist? (dedup)
      → If no: create Activity {
           type: 'email',
           direction: inbound | outbound,
           subject: email subject,
           content: email body (plain text),
           emailThreadId: Gmail threadId,
           emailMessageId: Gmail messageId,
           isRead: false (inbound) | true (outbound),
           opportunityId: found opportunity
         }
   d. If no match (unknown sender):
      → Check if email looks like an inquiry (heuristic)
      → If yes: surface in "Inbox Leads" queue
4. Update GmailConnection.historyId = latest historyId
5. Update GmailConnection.lastSyncedAt = now
```

### Inbox Leads Queue

When Gmail detects an email from an unknown sender that may be an inquiry:
- Appears in Pipeline board as a notification badge or a "Review inbox leads" panel
- Staff sees: sender name, email, subject, body preview
- Actions: "Create Lead" (creates Opportunity from email data) | "Ignore"
- "Create Lead" sets `opportunity.source = 'email'` and `opportunity.sourceEmailId = gmail messageId`

### Thread Grouping

Emails with the same `emailThreadId` are grouped visually in the Activity timeline:

```
📧 Email thread with John Smith — Deck Estimate       ● 3 days ago
   (4 messages)  [expand ▼]
   └─ You: "Hi John, your estimate is attached"       3 days ago
   └─ John: "Thanks, looks good. One question..."     2 days ago
   └─ You: "Happy to clarify — the membrane..."       2 days ago
   └─ John: "Perfect, let's proceed"                  Yesterday
```

---

## Entity Relationship Map

```
GmailConnection ────── Company ──── CompanySettings
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

   Invoice ──── Project
      │    └─── Estimate (estimateId)
   Payment[]
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
| `GmailConnection` | Supabase | OAuth tokens — encrypt at rest |
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
-- gmail_connections
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
4. Supabase: create `activity_comments`, `site_visits`, `project_photos`, `gmail_connections`, `company_settings`

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

**Phase 4 — Gmail:**
14. Gmail OAuth connection flow (Settings → Integrations)
15. Incremental sync worker
16. Inbox Leads queue UI
17. Email thread grouping in Activity timeline

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

#### Gmail Integration — Web Only (No iOS Implementation)

Gmail integration API routes exist on the web backend (`OPS-Web/src/app/api/integrations/gmail/`):
- `route.ts` — main Gmail integration endpoint
- `callback/route.ts` — OAuth callback handler
- `manual-sync/route.ts` — manual sync trigger

Supporting web services: `gmail-service.ts`, `use-gmail-connections.ts`, `integration-service.ts`, `integrations-tab.tsx`, `inbox-leads-queue.tsx`.

No Gmail integration exists on iOS. There are no Gmail-related Swift files in the iOS codebase.

---

*This document supersedes any prior informal notes about entity relationships. All implementation decisions should reference this document.*
