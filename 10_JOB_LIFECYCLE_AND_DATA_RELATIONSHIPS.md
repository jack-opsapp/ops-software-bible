# 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md

**OPS Software Bible — Complete Job Lifecycle: Inquiry → Close**

**Purpose**: Defines the complete data flow for a trade job from first contact through to a paid invoice. Documents all entity relationships, automation triggers, new entities, and required changes to existing entities. This is the master reference for how leads, pipeline, clients, estimates, projects, tasks, and invoices inter-operate.

**Last Updated**: August 4, 2026
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
- Staff starts a site visit from the FAB, captures client details onsite, then creates/links the lead from the visit identity panel
- Gmail integration — unrecognized inquiry email surfaced for staff review → "Create Lead"

**Card shows:** Contact name, source badge, rough estimated value, age in stage

**Auto-advance trigger:** First Activity logged → `qualifying`

> Implemented 2026-05-20 via Postgres trigger `tr_activities_first_log_auto_advance` (migration `2026-05-20-activities-first-log-auto-advance-trigger.sql`). Server-side, fires `AFTER INSERT ON activities` for any opp-attached activity where the opp is currently in `new_lead`. See `09_FINANCIAL_SYSTEM.md` § Stage Transitions for the full trigger semantics, idempotency guard, and the historical-backfill scope decision.

---

#### `qualifying`
Staff is assessing scope. Site visit may be booked.

**Actions available from card:**
- Log activity (call, meeting, site visit)
- Start or book site visit (creates/reuses SiteVisit — scheduling dates stored on the visit/task directly; CalendarEvent model has been removed)
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

**What happens automatically** — since 2026-06-03 both platforms call the unified `convert_opportunity_to_project` RPC (one atomic transaction; see §09 LeadConversionService → Unified conversion brain, migration `20260603020000_won_conversion_dedup_naming`). The legacy iOS `convert_lead_to_project` is now a thin shim over it (migration `20260603020001`), so the App-Store iOS build converges with no release.
1. `opportunity.stage = won`, `stage_entered_at = now`, `stage_manually_set = true`, plus one `stage_transitions` row — **idempotent**: skipped when the opp is already `won` (the estimate-approval path wins without converting), so converting an already-won deal never writes a second transition.
2. `opportunity.actualCloseDate = now`; `actual_value` recorded.
3. A `projects` row is created (`status = Accepted`) carrying `address` **and `latitude`/`longitude`** (the geocode is no longer dropped) — or, when the operator links instead of creates, an existing project is linked without touching its status/title.
4. Estimates relinked (`project_ref` + text `project_id` mirror); LABOR line items materialized as `project_tasks`; non-deleted site-visit photos attached as `project_photos` (`source='site_visit'`, `site_visit_id` back-linked, `uploaded_by = site_visit.created_by`). Tasks and photos are deduped by source, so a link-existing or a retry never double-inserts.
5. A `'converted_to_project'` disposition row is written.
6. Task Generation modal remains deferred — v1 silently materializes every LABOR line item with no per-task toggle.

**Dedup at convert (2026-06-03).** Before the dialog/sheet commits, both platforms call the read-only `get_conversion_preflight` (§09): it surfaces any project this opp already converted to (open it — no new project), likely-duplicate projects for the client by normalized address (high = same client + address; medium = same address, different client — **link** instead of create), and the client's other projects. This replaces the old iOS local-SwiftData-cache dedup (which missed unsynced projects) and closes the web gap that silently minted duplicate projects on repeat-client wins.

**Auto-naming (2026-06-03).** The new project's name is a self-healing pointer to its address (`projects.title_is_auto` + the `projects_autoname_biud` trigger — see §03). The operator never types a name in the common path; it is derived from the site address (street line → `{Client}'s Project` → `New project`), re-derives if the address is corrected, and auto-disambiguates same-name collisions with a silent ` #N`. A hand-typed name freezes it (`title_is_auto = false`).

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

### Around-call lead capture (iOS, feature 154cb8a3)

**Reset to AROUND-call, not in-call.** iOS gives a third-party (non-VoIP) app no custom in-call UI, no access to the system call log, and no way to create app data or open the app *during* a native Phone call. `CXCallObserver` reports call *state* only (never the number) and fires reliably only while OPS is foregrounded. So OPS captures calls *around* them, never inside them. All three entry points funnel into the existing data layer — `OpportunityRepository.create` (`source:"phone"`) + `LeadDetailViewModel.logActivity` (type `call`) — so the `new_lead → qualifying` auto-advance fires exactly as for any other first activity.

1. **Outbound post-call prompt.** Tapping CALL on a lead's `ContactCard` records an outbound intent (`CallLogStore`, persisted to UserDefaults so it survives the app→Phone→app switch). On the next foreground, `MainTabView` reads the recent intent (≤30 min) and presents `LogCallSheet` pre-filled to that exact lead. `CallStateObserver` adds an immediate trigger when a call ends while OPS stays foregrounded.
2. **FAB "Log a call".** Opens `LogCallSheet` in capture mode → pick a contact (`CNContactPicker`) or type a number → OPS dedups it (`PhoneNumber.normalize` + `OpportunityRepository.matchLead`) and **attaches** to the existing lead, or **creates** a new `source:"phone"` lead. Dedup is **network-based**: opportunities are NOT persisted to SwiftData (the pipeline list is network-only), so the sheet fetches the candidate set once on open, matches locally as the operator types, and re-checks before creating. The post-call path skips dedup entirely — it carries the recorded `opportunityId` straight through so it always attaches to the exact lead called.
3. **App Shortcut "Log a call to OPS".** `LogCallToOPSIntent` + `OPSAppShortcuts` in the **main app target** (no extension, no entitlement) — one tap from Siri / Spotlight / Action Button / Control Center. `openAppWhenRun` brings OPS forward and routes through the shared `CallCaptureCoordinator` into the same sheet.

**Gating.** Every entry point matches the pipeline-mutation posture: feature flag `pipeline` enabled + permission `pipeline.manage` (the same gate as the existing "Log Activity" FAB item).

**Voice note (not call recording).** Recording a native call's audio is not possible for a third-party app — iOS exposes no API. The shipped substitute is an in-app voice note: the operator dictates after the call via mic + **on-device** `SFSpeechRecognizer` (`requiresOnDeviceRecognition`, so audio never leaves the phone), transcript folded into the activity `body_text`. Canada is one-party consent; the operator's own dictation is lawful. Never marketed as "call recording."

**Presentation reliability (updated 2026-07-07).** `CallCaptureCoordinator.present` defers one pending request when another call-capture sheet is already active instead of dropping the shortcut/FAB action. `MainTabView` presents deferred captures immediately after the active sheet clears, before draining older post-call or shortcut queues. Manual voice-note stop now flushes transcription after the `recording -> stopping -> idle` transition, so dictated text lands in the note before save.

**Provenance.** `call_source` / `caller_number` / `call_started_at` on `activities` (see `03_DATA_ARCHITECTURE.md` § Activity) — additive, nullable.

**Deferred (externally gated).** A CallKit **Call Directory** *recognition* extension could label inbound pipeline numbers as "OPS lead: {name}" on the native incoming-call screen. It's pure recognition (no data write) but is the only piece needing a new `.appex` target + `com.apple.developer.callkit.call-directory` entitlement + App Group + portal provisioning — out of scope for this build, flagged for a future scheduled migration.

### Client picker phone-contact blending (iOS, feature 388663d4)

**The client picker reads the device address book so a client you already have as a phone contact is one tap from being an OPS client.** Two surfaces share the behavior: the create-project client field (`ProjectFormSheet`) and the change-client sheet (`ClientPickerSheet`).

- **Inline blend.** As the operator types, matching device contacts that are **not already in OPS** appear *inline* beneath the OPS client matches, each tagged with an `IN CONTACTS` badge (`PhoneContactRow`). Unbadged rows are existing OPS clients — the badge is the only signal needed (origin, not a separate list or button).
- **Not-in-OPS dedupe.** `PhoneContactSearch` (pure, unit-tested) matches contacts by name / phone (digits-only, format-insensitive) / email, then `ClientIdentityIndex` drops any contact already represented by an OPS client **or sub-client** (by name, phone, or email) so only genuinely-absent contacts are badged. Intra-address-book duplicates collapse too.
- **Background create on select (reliability fix 2026-07-17).** Tapping a badged row creates the OPS client in the background via `PhoneContactImporter` — the single shared path that also backs the manual "import from contacts" button (feature 33403492): avatar uploaded to S3 when present and the client persisted through `DataController.createClientModel`. That exact context-managed saved client returns immediately, so the project form selects it (or the change-client sheet assigns it via `onSelect`) even when the secondary pipeline write is offline or rejected. `ClientLeadAutocreateQueue` durably seeds the matching lead with the same behavior as `ClientSheet.createNewClient`: one pending item per client, retries across app/network boundaries, account-scope revalidation after every network await, and existing-linked/keyed-opportunity readback. Automatic inserts use `source_thread_key = client-autocreate:<client-id>`, protected by the live unique `(company_id, source_thread_key)` constraint, so overlapping/ambiguous retries remain one lead without a new migration. `ClientCreatedSuccess` fires with the existing `PIPELINE LINK QUEUED` state while delivery is pending; lead delivery failure never reports the saved client as `SAVE FAILED`.
- **Access + degradation.** Contacts permission (`NSContactsUsageDescription`, already shipped) is requested lazily on first client-field focus / first keystroke — never in tutorial mode. A denial degrades silently to OPS-only; the out-of-process `CNContactPicker` import button (permission-free) remains as the manual fallback. The lightweight searchable index is built off the main thread and the full `CNContact` (image + postal) is re-fetched by identifier only at import time (`PhoneContactsProvider`).

---

## Data Model Changes (Modified Entities)

### `LineItem` (Supabase) — MODIFIED

Adds `type`, `taskTypeId`, `estimatedHours`, and the Phase 13 configuration-snapshot fields:

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

  // --- task-generation fields ---
  type: LineItemType;                  // LABOR | MATERIAL | OTHER
  taskTypeId: string | null;           // Bubble TaskType ID — LABOR items only
  estimatedHours: number | null;       // optional, for labor costing

  // --- Phase 13 configuration snapshot ---
  configuredOptions: jsonb | null;       // {option_id: option_value_id_or_int_or_bool}
  resolvedUnitPrice: number | null;      // base + applicable modifiers, frozen at line creation
  resolvedOptionsLabel: string | null;   // "TM · Black · Concrete · 4 corners"
}
```

**Rules:**
- `type` defaults to `LABOR` when linked from a Product with `type = 'LABOR'`
- Only `LABOR` line items participate in task generation
- `MATERIAL` and `OTHER` items are billing-only — no tasks created
- `taskTypeId` is nullable: a LABOR item without a taskTypeId generates one generic task

**Phase 13 snapshot semantics (line items as signed contracts):**

When a line item is created — manually from the line-item editor or programmatically by the drawing→estimate adapter — `ProductConfigurationResolver` runs:

1. Reads the chosen `Product`'s `ProductOption` rows + the user's choices.
2. Walks `ProductPricingModifier` rows whose triggers match. Modifier kinds:
   - `add_per_unit` → `unit_price += amount`
   - `add_flat` → `unit_price += amount`
   - `add_per_count` → `unit_price += amount * configured_options[option_id]`
   - `multiply_unit_price` → `unit_price *= amount`
3. Snapshots the resolved values to the line:
   - `configured_options` (jsonb) — the user's choices keyed by option id
   - `resolved_unit_price` — frozen final unit price
   - `resolved_options_label` — printed-estimate-friendly summary

Once written, these fields **never re-resolve**. Edits to the Product's options/modifiers/recipe after line creation do not retroactively change the estimate. This preserves the contract semantics of the estimate document.

The `configured_options` jsonb is also the input that `RecipeResolver` reads at install task creation (see § Cut-List Materialization below).

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

### `Product` (Supabase) — MODIFIED (Phase 13)

Phase 13 expanded the Product schema to support both barebones and configurable Products. See `09_FINANCIAL_SYSTEM.md` § Products & Services Catalog and `03_DATA_ARCHITECTURE.md` § 21 (Product) for the canonical schema.

Key Phase 13 additions:
- `basePrice` (replaces `defaultPrice` as the primary unit price column; `default_price` mirrored via Postgres trigger until ops-web cuts over)
- `pricingUnit` enum: `each` / `flat_rate` / `linear_foot` / `sqft` / `hour` / `day`
- `kind` enum: `service` / `good`
- `sku`, `isFavorite`, `minimumCharge`, `minimumQuantity`, `showBomOnEstimate`, `showInStorefront`, `tieredPricing` (jsonb)
- `unitId` FK to `catalog_units.id`
- Wire-field bug fixed — DTO no longer writes to non-existent `unit_price`/`cost_price` columns

Configurable Products carry zero-or-more rows in four extension tables: `product_options`, `product_option_values`, `product_pricing_modifiers`, `product_materials`. A "barebones" Product has zero rows in every layer and behaves identically to a flat product.

**Catalog-driven task auto-fill** (preserved from earlier behavior): when a user adds a Product to an estimate, `product.type` and `product.taskTypeId` automatically populate the line item; the line item's resolved configuration is captured at creation by `ProductConfigurationResolver`.

---

### Cut-List Materialization (Phase 13)

When a project transitions to `.inProgress` and install tasks are generated, recipes resolve to concrete `task_materials` rows pinned to specific `catalog_variants`. This is the canonical cut list the field crew works against.

**Lifecycle:**

```
Estimate approved
  └─ Project status → .accepted
      └─ Tasks auto-generated from LABOR line items (existing flow)
          ↓
Project status → .inProgress (install begins)
  └─ For each ProjectTask with sourceLineItemId:
       1. Load line.configured_options snapshot
       2. Walk ProductMaterial rows for line.productId:
            - Variant-pinned (catalog_variant_id non-null) → use directly
            - Family-pinned (catalog_item_id non-null) → resolve variant_selector against
              configured_options, find the matching variant on that family
       3. Multiply quantity_per_unit by line.quantity
            (and by configured_options[scaled_by_option_id] if scaled_by_option_id set)
       4. Insert task_materials rows pinned to specific catalog_variant_ids
```

`CutListMaterializer` lives in `OPS/Network/Sync/`. Resolution is **idempotent** — re-running for the same task replaces the existing rows in a single transaction. This means an estimate edit (recipe change, option change) followed by a re-materialization gives the field crew the latest cut list without leaving stale rows behind.

**Why install-time, not estimate-time?** The cut list must reflect the configuration the customer signed. Resolving at install creation means:
- Pricing was already frozen on the line item — recipe re-resolution doesn't affect billing.
- Stock state is fresh — variant SKUs that were active at estimate time but later marked inactive can be replaced by an admin before install.
- Family-level recipe edits can flow into pending installs without rebuilding old estimates.

`task_materials` rows write through the legacy `inventory_item_id` column too (null for new rows) — the field crew's view-layer is unchanged; only the FK column it reads has been swapped.

### Inventory-Tracked Estimate Acceptance (Phase 6 Draft)

Phase 6 adds an explicit company inventory mode before estimate acceptance can create material demand. `company_inventory_settings.inventory_mode` is the switch: `off` means accepting an estimate creates the job without projected stock rows; `tracked` means the acceptance transaction resolves accepted estimate lines into projected demand, allocation, and snapshot records.

Projected demand is planning pressure, not physical stock movement. `project_material_demands` records what the booked job is expected to need, including warning rows for missing product-to-stock mappings. `task_material_allocations` links projected demand and eventual task cut-list rows to `catalog_stock_units`, but rows with `allocation_status = 'projected'` or `overrun` must not update `catalog_variants.quantity`, write `inventory_deductions`, or write `catalog_stock_unit_events`.

Material history is immutable. `project_material_snapshots` is the header for booking, release, crew adjustment, and task-consumption snapshots; `project_material_snapshot_items.stock_unit_snapshot` stores the stock-unit identity and measurements as JSON at the moment the snapshot is written. Later edits to a roll, offcut, or lot cannot rewrite the historical booking view.

Actual stock deduction remains a task-completion event. The approved completion path derives work from task-scoped `project_material_demands`, resolves live `catalog_stock_units`, writes consumed/unavailable `task_material_allocations` evidence, writes `inventory_deductions`, writes `catalog_stock_unit_events`, updates the affected stock units, and stamps a `task_completion_consumption` snapshot. Shortage stays as overrun allocation; physical stock-unit values never go below zero.

Missing product-to-stock mappings are non-blocking. Estimate acceptance can proceed with warning payloads and keyed persistent `catalog_mapping_needed` notifications routed to Catalog Setup. Those notifications resolve by `dedupe_key` only after the mapping gap is recomputed as closed.

The Phase 6 P6-3 project/task sync draft adds `private.sync_accepted_estimate_project_tasks(p_estimate_id uuid)` in `migrations/2026-05-27-03-ios-catalog-p6-estimate-acceptance-task-sync.sql`. The helper is private and does not expose a public estimate-acceptance RPC. It derives the actor server-side, verifies the caller's company, requires live estimate/project/task/pipeline permissions, creates or reuses the opportunity-backed project, links the accepted estimate, verifies one active `project_tasks` row per selected LABOR line item by `source_estimate_id` + `source_line_item_id`, and idempotently links site visits/photos. It performs no material demand calculation; P6-6 is the public wrapper that calls this helper and tracked-inventory material demand in one server transaction.

The Phase 6 P6-5 booking-warning draft adds `private.persist_estimate_material_booking_projection(p_estimate_id uuid, p_project_id uuid)` in `migrations/2026-05-27-05-ios-catalog-p6-booking-warnings.sql`. The helper is still private: it runs only inside the P6-6 acceptance transaction, calls the P6-4 JSONB demand planner, persists projected demand idempotently by `demand_key`, supersedes stale projected/warning rows for the same estimate/project, releases open rows when inventory mode is `off`, records `booking_projection` evidence, and writes only non-deductive overrun allocation rows. It does not require `catalog.manage`; material writes are authorized by the acceptance transaction guard, same-company checks, and the same estimate/project/task/pipeline permissions required to accept the estimate.

The Phase 6 P6-6 acceptance draft adds `public.accept_estimate_to_job(p_estimate_id uuid, p_idempotency_key text)` in `migrations/2026-05-27-06-ios-catalog-p6-acceptance-transaction-and-mapping-notifications.sql`. The wrapper is caller-scoped, grants execute only to `authenticated`, calls P6-3 and P6-5 in one transaction, and creates persistent keyed `catalog_mapping_needed` notifications only from the P6-5 `missing_mappings` array. Companies with inventory mode `off` accept successfully without booked-job material rows; tracked companies still get projected demand, booking warnings, overrun allocation evidence, and booking snapshots without stock deduction.

The Phase 6 P6-20 task-completion contract applies `public.complete_project_task(p_task_id uuid, p_idempotency_key text, p_material_adjustments jsonb)` and `private.consume_task_materials_for_completed_task(p_task_id uuid, p_idempotency_key text, p_material_adjustments jsonb)` through migration `2026_05_28_02_ios_catalog_p6_task_completion_consumption_contract` (version `20260529062017`) from `migrations/2026-05-28-02-ios-catalog-p6-task-completion-consumption-contract.sql`. The public wrapper owns the task status transition and invokes the private material helper in the same transaction. The helper treats inventory mode `off` as a stock-movement no-op, derives consumable work from task-scoped `project_material_demands`, resolves live stock units at completion, writes consumed/unavailable allocation evidence, preserves exact stock-unit snapshots, and never lets stock-unit quantity or length go below zero.

iOS Catalog OPS P6-22 wires the field-app completion surface to that contract. `DataController.updateTaskStatus(task:to:)` and `DataController.updateTask(task:)` continue to complete tasks locally first for offline-first UX, but completed task sync payloads carry a stable `ios:complete_project_task:<task_id>` idempotency key and empty material-adjustment object. `OutboundProcessor.handleProjectTask` sends completed updates and completed offline creates through `public.complete_project_task`; non-completion status changes keep the existing status-update behavior.

iOS Catalog OPS P6-27 (2026-05-29) wires the inventory-mode on/off control and off-mode gating into the field app. `CompanyInventoryModeRepository` (with the `InventoryModeClient` test seam) reads `company_inventory_settings.inventory_mode` (a missing row resolves to `off`, never `tracked`) and writes through `public.set_company_inventory_mode(p_company_id, p_inventory_mode)`. The shared `InventoryModeControl` (driven by `InventoryModeViewModel`) renders the toggle in two surfaces per Closed PM Decision 4: the Catalog Setup review step (`CatalogSetupFlowSheet`) and Company Settings (`SettingsView` → OPERATIONS → "Inventory Tracking" → `InventoryTrackingSettingsView`). Both entries are gated to the granular `catalog.manage` permission via `PermissionStore.can("catalog.manage")` — never by role. Switching to `off` always routes through a confirmation dialog explaining that open projected demand is released while history (snapshots, stock-unit events, prior deductions, consumed demand) is preserved; the server RPC owns the release and snapshot writes, and the UI re-reads server truth on write failure. Off-mode gating also reaches read surfaces: `EstimateDetailView`'s accepted-acceptance banner only shows STOCK OVERRUN / STOCK MAPPING / material-warning language when the acceptance response reports `inventory_mode == 'tracked'`, and `TaskDetailsView` hides the Material History card entirely when the company mode is `off` (resolved from `company_inventory_settings`, never inferred from absent demand rows) and renders every evidence line — no four-row cap.

---

### Drawing → Estimate Adapter (Phase 13)

The Deck Builder canvas can emit a fully-populated draft Estimate in one tap. This is the most consequential time-saver in the catalog redesign — hours of estimate writing collapse into a single button. The deck side closed the loop in 2026-05-07: `ComponentEmitter` projects geometry into the catalog's `components[]` vocabulary on every save, the adapter resolves Products + options, and the merge layer reconciles the result with the legacy geometry-driven path.

**Entry point:** Deck Builder canvas → toolbar `Estimate` button → `EstimatePreviewSheet` → "Create Estimate". One button, one flow — the merge layer routes adapter-vs-legacy per component_type based on company state. (UX decision per the deck-catalog spec § 7 — single entrypoint avoids parallel surfaces.)

**End-to-end flow** — drawing → components → adapter → line_items → task_materials:

```
User taps Estimate button on Deck Builder
   ↓
DeckBuilderViewModel.save()
   ├─ DeckDrawingData.toJSON() runs
   │     └─ ComponentEmitter.emit(self) populates `components[]` from
   │        canonical geometry — one row per railing / post_set /
   │        stair_set / deck_board / gate, plus additive Phase 2
   │        structural rows for joist / beam / post / rim_joist /
   │        blocking when drawing_data.framing exists. Per-edge
   │        railing linear_feet is net of stair span and gate widths;
   │        deck_board sqft is per-detected-face; multi-level
   │        connection stairs carry level_id pinned to the upper level.
   └─ drawingDataJSON written with up-to-date components projection
   ↓
DeckBuilderViewModel.mergedCatalogLineItems()
   ├─ DesignToEstimateAdapter.generate(design, companyId, modelContext)
   │     ├─ Parse drawing_data → walk components[]
   │     ├─ For each component:
   │     │    1. Look up company_default_products[component_type] → Product
   │     │    2. For each ProductOption: pull $design.<key> from metadata,
   │     │       fall back to default_value if missing
   │     │    3. Compute quantity from pricing_unit + metadata
   │     │       (linear_feet, sqft, count, tread_count, etc.)
   │     │    4. Apply ProductPricingModifier rows → resolved_unit_price
   │     │    5. Snapshot configured_options + resolved_unit_price +
   │     │       resolved_options_label
   │     └─ Emit GeneratedLineItem carrying componentType + snapshot
   │
   └─ EstimateGeneratorService.generateLineItems(drawingData)
         └─ Walks vertices/edges/surfaces/connections — emits flat
            rows with categories Surface / Substructure / Railing /
            Stairs / Connecting Stairs / Other, plus warnings (missing
            elevation, AR accuracy notes, multi-level narrative)
   ↓
CatalogEstimateMerger.merge(adapterItems, legacyItems, defaultsCovered)
   ├─ Adapter rows kept (sorted first)
   ├─ Legacy rows in covered categories dropped:
   │     railing or post_set → drop "Railing"
   │     stair_set            → drop "Stairs", "Connecting Stairs"
   │     deck_board           → drop "Surface"
   │     gate                 → drop nothing
   │     structural rows      → currently skipped until the enum-backed
   │                            product-default vocabulary is extended
   ├─ Legacy rows in uncovered categories pass through
   └─ Warning rows always pass through
   ↓
DeckBuilderViewModel.generateEstimate() persists
   ├─ CatalogEstimateMerger.groupByTaskType(merged, taskTypes)
   ├─ For each group:
   │     - parent CreateLineItemDTO (LABOR / OTHER)
   │     - per child:
   │         * configuredOptions (RawJSONColumn) ← adapter-only
   │         * resolvedUnitPrice                ← adapter-only
   │         * resolvedOptionsLabel             ← adapter-only
   │         * (legacy children leave those fields nil)
   └─ line_items rows persist via EstimateRepository
   ↓
[Project transitions to .accepted → tasks auto-generate from LABOR rows]
   ↓
[Project transitions to .inProgress]
   ↓
CutListMaterializer.materialize(forLineItem:projectTaskId:)
   ├─ Reads line.configured_options snapshot
   ├─ RecipeResolver.resolve(materials, configuredOptions, ...)
   │     - Variant-pinned recipe rows → use directly
   │     - Family-pinned + variant_selector → resolve $option.<name>
   │       to a CatalogOptionValue, match candidate variants
   │     - Scale by configuredOptions[scaledByOptionId] when set
   └─ TaskMaterialRepository.createMaterials([CreateTaskMaterialDTO])
   ↓
task_materials rows pinned to concrete catalog_variant_ids
   = the cut list the field crew works against
```

**Resilience at every hop:**

- `components[]` missing on legacy `drawing_data` JSON → `DeckBuilderViewModel.init` backfills via `ComponentEmitter.emit` so the adapter sees a populated projection on first load. Designs the user never reopens stay legacy on disk; adapter no-ops on them.
- `company_default_products[component_type]` missing → adapter skips the component silently. Merger then falls through to legacy for that category.
- Phase 2 framing rows (`joist`, `beam`, `post`, `rim_joist`, `blocking`) are additive projection rows. They are safe to persist before catalog/web product-default support lands because unknown or unmapped rows skip rather than failing the estimate flow.
- Line items without `configured_options` (legacy rows or barebones flat products) → `CutListMaterializer.materialize` returns 0 rows (no recipe to resolve); install task carries no `task_materials` and the field crew works from the line item directly.
- ops-web round-trips the same `drawingDataJSON`. The components key is forward-compatible (web ignores keys it doesn't recognize). If web strips the key on save, iOS backfills again on next load.

**Reserved metadata keys per `component_type`** — emitted by `ComponentEmitter`, consumed by the adapter via `option_default_source = "$design.<key>"`:

| Component | Metadata keys |
|---|---|
| `railing` | `linear_feet`, `corners_count`, `color`, `mount_type`, `mount_surface`, `edge_id`, optional `level_id`, optional `wall_material` for `parapet_wall` |
| `post_set` | `count`, `height`, `color`, `mount_type`, `edge_id`, optional `level_id`; omitted for `parapet_wall` |
| `stair_set` | `tread_count`, `width`, `color`, `mount_type`, `edge_id` OR `connection_id`, `level_id` (multi-level) |
| `deck_board` | `sqft`, `color`, `material`, `surface_id`, optional `level_id` |
| `gate` | `count`, `width`, `color`, `mount_type`, `mount_surface`, `edge_id`, optional `level_id` |
| `joist` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `beam` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `post` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `rim_joist` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `blocking` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |

Adding new metadata keys is fine; renaming or removing breaks the adapter contract — see `OPS/DataModels/Supabase/Catalog/CompanyDefaultProduct.swift` (`DesignComponentType` enum) and `OPS/Services/DesignToEstimateAdapter.swift:148-173` (`computeQuantity`).

**Position in the project lifecycle:**

```
Lead/inquiry → Opportunity created
  ↓
Site visit / scope captured
  ↓
Drawing produced in Deck Builder (component_type tagged on each component)
  ↓
USER TAPS GENERATE ESTIMATE  ← drawing→estimate adapter runs here
  ↓
Draft estimate appears with all line items snapshotted
  ↓
User reviews/edits → sends estimate
  ↓
Customer approves → project created → tasks generated → cut list materialized
```

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

## Recurring Task Lifecycle (Phase 3 — added 2026-04-27)

Recurring tasks short-circuit the estimate-driven task generation pipeline. They live as `task_recurrences` templates that the cron worker `/api/cron/recurrence-generate` materializes into concrete `project_tasks` rows on a 60-day rolling horizon. Generated occurrences are otherwise normal tasks — schedulable, completable, deletable.

### Flow diagram

```
                ┌──────────────────────────────────────────┐
  USER ACTION   │ Repeat picker on task detail panel       │
                │ Selects: Off / Daily / Weekly / ... /    │
                │ Custom (RFC 5545 RRULE editor)           │
                └────────────────────┬─────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────┐
  TEMPLATE      │ task_recurrences row                     │
  CREATED       │   rrule, start_anchor, end_anchor,       │
                │   all_day, start_time, end_time,         │
                │   duration, team_member_ids,             │
                │   next_generation_at = NOW()             │
                └────────────────────┬─────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────┐
  CRON RUN      │ /api/cron/recurrence-generate every 4h:  │
                │ 1. SELECT WHERE next_generation_at<=NOW()│
                │ 2. RRule.between(NOW, NOW+60d)           │
                │ 3. For each candidate:                   │
                │    - lookup exception (skip / override)  │
                │    - INSERT project_tasks (recurrence_id │
                │      + recurrence_origin_date)           │
                │    - emit `schedule_change` notification │
                │ 4. UPDATE next_generation_at = NOW+4h    │
                └────────────────────┬─────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────┐
  CALENDAR      │ project_tasks row visible in Day / Week /│
                │ Month / Crew / Hourly views just like    │
                │ any one-off task. Drag / edit triggers   │
                │ the recurrence-edit prompt.              │
                └────────────────────┬─────────────────────┘
                                     │
                  ┌──────────────────┼──────────────────┐
                  │                  │                  │
                  ▼                  ▼                  ▼
            ┌─────────┐      ┌──────────────┐    ┌──────────┐
            │ this    │      │ this+follow  │    │ all      │
            │         │      │              │    │          │
            │ exception│     │ cap original │    │ patch    │
            │ row +   │      │ end_anchor;  │    │ original │
            │ patch   │      │ fork new tpl;│    │ template │
            │ task    │      │ re-point     │    │ (cron    │
            │         │      │ future tasks │    │ regens)  │
            └─────────┘      └──────────────┘    └──────────┘
```

### Idempotency

`uq_project_tasks_recurrence_origin` on `(recurrence_id, recurrence_origin_date) WHERE recurrence_id IS NOT NULL AND deleted_at IS NULL` prevents duplicate inserts on cron re-runs. The cron also pre-fetches existing origins per-recurrence so it skips before attempting the insert (avoiding 23505 noise in logs).

### Soft-delete semantics

`RecurrenceService.softDelete(templateId)` cascades:
1. `task_recurrences.deleted_at = NOW()` — template no longer runs in the cron.
2. `project_tasks.deleted_at = NOW()` for every row where `recurrence_id = templateId AND status = 'active' AND start_date > NOW()` — un-started future occurrences disappear.
3. Past, in-progress, and completed occurrences are preserved as historical records.

### Notification fan-out

Every materialized occurrence fires a `schedule_change` notification per assigned crew member (`team_member_ids`). The web notification rail (Section 14, Edge Tab) picks them up via TanStack Query polling. iOS users will see them via the existing OneSignal push channel once iOS adopts the `recurrenceId` columns (planned post-Phase-3).

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

**iOS authoring (2026-05-11 — bug 4dadd96c)**: `TaskTemplate` rows are
authored from inside `TaskTypeSheet`'s `DEFAULT SUB-TASKS` section
(edit-mode only — the parent task type id must exist before templates
can pin to it). Each template carries `task_type_ref` (uuid FK) and
`task_type_id` (legacy text mirror) so legacy reads and new reads land
on the same parent. Sub-tasks are managed by `TaskTemplateEditSheet`
(create / edit / soft-delete) and synced via
`TaskTemplateRepository`. The Supabase table is `task_templates` —
schema unchanged from the original Bubble-era design.

**Related iOS surfaces for the catalog interlink** (same bug):
- Product create / edit forms now expose `task_type_ref` via a required
  picker for LABOR products (optional for Material / Fee). See bible
  section `03_DATA_ARCHITECTURE.md` § 3 → "Catalog interlink surfaces
  on iOS" for the full set of surfaces and component file paths.
- `TaskTypeMergeSheet` now re-pins linked products and templates onto
  the merge target so neither is silently orphaned on the deleted
  source row.

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

> **Durable sync status (production database/web contract live 2026-08-02):** Lead detail, New Lead, and the FAB open `ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift`; the FAB can start without a lead. Parent, identity draft, evidence artifacts, and per-visit checklist snapshots have an atomic phone outbox, normalized Supabase contract, inbound delta/Realtime reconciliation, cross-device resume, guarded completion, and protected logout recovery. The normalized schema and invoker-safe completion boundary are live in production; the updated iOS client is committed and simulator-verified but is not customer-distributed until its signed device/App Store gate completes.

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
BOOK SITE VISIT (from Opportunity card, New Lead, FAB, or Calendar)
  → SiteVisit created (status: scheduled)
  → SiteVisit scheduled (scheduling dates stored on SiteVisit/task directly; CalendarEvent model removed)
  → Activity auto-logged: "Site visit scheduled — Feb 20 @ 10am"
  → Opportunity stage → qualifying (if currently new_lead)

START SITE VISIT FROM FAB
  → Capture console opens immediately, with no lead pre-step
  → SiteVisit created with opportunityId = null until the operator links or creates the lead
  → Operator can search active leads/clients inside the same console
  → If lead exists: bind the visit and all active packet records to that opportunity
  → If only the client exists: bind client details and keep capturing until the lead is created
  → If neither exists: fill client/contact/address fields inline and create the lead from the identity panel when connection is available

ON-SITE (staff opens visit on mobile/web)
  → SiteVisit.status → in_progress
  → Parent + SyncOperation commit together on the phone
  → SiteVisitIdentityDraft autosaves client/contact/address fields and queues behind the parent
  → Primary form order is deterministic:
      identity
      optional read-only summary from the currently bound lead's trimmed opportunities.ai_summary
      checklist
      notes
    A blank/whitespace summary renders no section; the form performs no second fetch, exposes no summary editor, and never substitutes email_threads.ai_summary
  → Selected company SiteVisitType fields snapshot into cloud-backed SiteVisitChecklistAnswer rows
  → If the attached lead, client, or address is wrong:
      Operator expands the lead/client panel
      Corrects address/contact/client fields inline
      Or reassigns the entire capture packet to another active lead
  → Staff captures photos rapid-fire
  → Staff dictates or types notes; iOS autosaves one live draft artifact as text changes
  → Staff records measurements
  → Staff reviews captured photo thumbnails, opens zoomable previews, and marks up captured photos
  → If deck_builder is enabled and the user can create/edit designs:
      Staff creates the CanPro deck design during the site visit
  → If dimensioned capture is available:
      iOS opens DimensionedCaptureView during the visit
      Operator captures/annotates the measured photo before leaving site
      SiteVisitDimensionedCaptureStore saves a local dimensioned-photo artifact
  → Checklist fields autosave as the operator answers them
  → Photo, measurement, and deck-design checklist fields can use the matching captured evidence already in the packet
  → Operator can add ad-hoc checklist questions during the visit
  → Original/rendered/thumbnail media upload to a server-derived visit object key
      Assets at or below 10 MiB pass byte-for-byte
      Oversized rasters use an ephemeral outbound JPEG capped at 2,048 px and 10 MiB
      Durable originals remain unchanged on the phone
  → Another authorized device can pull and resume the in-progress packet

MARK COMPLETE
  → Phone atomically queues any final edits/media and one guarded completion command
  → // VISIT SAVED confirms durable phone custody; Pending Work remains visible until server ACK
  → public.complete_site_visit_guarded locks/authorizes the parent
  → SiteVisit.status → completed, completedAt = first completion time
  → Exactly one Activity is inserted/reused on the related timeline:
      type: site_visit
      subject: "Site visit completed"
      content: siteVisit.notes (preview)
      siteVisitId: siteVisit.id
  → Operator reviews which packet artifacts pipe into the project
  → Project creation stays blocked until a lead is linked and required checklist answers are complete
  → Create Project opens the normal conversion flow with the packet staged

JOB WON (opportunity converts to project)
  → For each reviewed photo artifact:
      Existing remote visit object reused by ProjectPhoto
      source = 'site_visit', siteVisitId = siteVisit.id
      active (company, project, visit, URL) uniqueness prevents retry duplicates
  → Reviewed notes/transcripts/measurements become a project note
  → Answered checklist fields become additive structured checklist_items[] in the same project note while legacy content + checklist[] remain for older clients
  → Reviewed deck-design artifact attaches the standalone DeckDesign to the project
  → Photos appear in project gallery under "Site Visit" group
```

**SiteVisitService methods:**
- `createSiteVisit(data)` — creates the visit; scheduling activity/calendar behavior remains owned by the calling surface
- `startSiteVisit(id)` — status → in_progress
- `completeSiteVisit(id, data)` — calls `complete_site_visit_guarded`; completes and creates/reuses one activity atomically
- `cancelSiteVisit(id)` — status → cancelled
- `POST /api/uploads/presign` with `targetType=site_visit` — authorizes the active visit and derives `site-visits/{company}/{visit}/{artifact}/{variant}.{ext}`
- `fetchSiteVisitsForOpportunity(opportunityId)` — all visits for a lead
- `fetchSiteVisitsForProject(projectId)` — all visits for a project

**Failure/recovery rules:** the phone drains parent → children → media → completion and safely retries every step. A missing legacy parent is reconstructed only from exact same-company, valid, non-conflicting child evidence. Unsafe evidence is encrypted and shown as protected Pending Work with no generic Retry. If the server later restores an exact deleted parent, a newer authoritative same-company inbound merge may release only that visit's quarantined operations; the rows and media stay in place and the same sync cycle retries them. Voluntary logout waits briefly for a real server ACK and asks before discard; forced logout encrypts unsent packets/media for the exact user+company before wiping shared SwiftData. Another signed-in account cannot see or delete that vault.

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
  lastSyncHistoryId: string | null;  // Gmail historyId or versioned M365 folder cursor
  lastSyncAt: Date | null;
  historyRecoveryAnchor: Date | null;       // Gmail expired-history replay lower bound
  historyRecoveryPageToken: string | null; // durable messages.list continuation
  historyRecoveryTargetToken: string | null; // fresh historyId held until replay completes
  opsLabelId: string | null;        // Gmail label ID or M365 category ID
  webhookSubscriptionId: string | null;
  webhookExpiresAt: Date | null;
  webhookClientStateHash: string | null; // SHA-256; M365 only
  aiReviewEnabled: boolean;
  aiMemoryEnabled: boolean;
  status: 'active' | 'paused' | 'error' | 'setup_incomplete' | 'needs_reconnect' | 'disconnected';
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

**Trigger:** guarded site-visit completion transaction

**Flow:**
1. `complete_site_visit_guarded` completes the visit and inserts/reuses one Activity (`type: site_visit`) in the same transaction
2. Prompt: "Ready to build an estimate?" (dismissible)
3. If Yes → open Estimate creation form pre-linked to this opportunity → `opportunity.stage → quoting`

**iOS review sheet (bug 56c37df2 follow-on, site-visit report).** The review
sheet has two exits, and completing a visit must **never** auto-convert the
lead to WON:
- **SAVE VISIT** (primary) — commits the complete packet and completion command
  durably on the phone, then drains it to the guarded server transaction. The
  `// VISIT SAVED` toast confirms local custody; Pending Work remains visible
  until the server ACK. The completion transaction posts the timeline activity exactly once
  and the phone moves the bound lead to the operator-selected stage. The default comes
  from `SiteVisitStageDefault.defaultStage(current:)`: a `new_lead` advances to
  `qualifying`; a lead already in flight holds (never regresses); a terminal
  lead is never touched. The operator can pick any non-terminal stage from the
  "LEAD STAGE AFTER VISIT" chips (won/lost/discarded are excluded). No project
  is created.
- **CREATE PROJECT** (secondary, explicit opt-in) — the conversion path
  (`ConvertToProjectSheet`), which is where WON + project creation happens.
  Reachable only when the visit has project-ready evidence and a bound lead.

---

### Automation E: Opportunity Won → Attach Site Visit Photos

**Trigger:** `opportunity.stage → won`

**Flow:**
```
For each SiteVisit WHERE siteVisit.opportunityId = opportunity.id:
  For each reviewed active photo artifact:
    Reuse its existing remote object URL in ProjectPhoto {
      projectId: opportunity.projectId,
      url: photo,
      source: 'site_visit',
      siteVisitId: siteVisit.id,
      uploadedBy: siteVisit.createdBy,
      takenAt: artifact.capturedAt
    }
  Retry resolves the same active row by (company, project, visit, URL)
```

### Automation E2: Conversion → Attach Inbound Email Photos (provenance repair 2026-08-17)

A sibling automation projects **customer-emailed images** into the converted project's gallery through the durable `email_conversion_photo_jobs` ledger (a `converted_to_project` event enqueues one `materialize` job per eligible attachment; a leased worker stages the object and `public.complete_email_conversion_photo_job` publishes it as a `project_photos` row).

**Provenance rule (migration `20260811232704_quoted_email_photo_provenance_dedup.sql`, applied 2026-08-17):** an image is eligible only when it is a stored, attributed, **inbound** attachment on an exact-matching email activity, and

1. **not owner-authored** — identical bytes the operator sent earlier in the same provider thread *or* the same opportunity disqualify it, even when Gmail splits the reply into a new thread (the reply envelope is inbound, the photo is still ours); and
2. **first inbound copy only** — of identical bytes on one opportunity, only the earliest eligible attachment may project; quoted/forwarded re-sends are duplicates.

Eligibility is enforced in three layers so it cannot regress: `private.email_conversion_photo_source_is_eligible` gates enqueue + completion, the `email_attachments` / `activities` triggers re-reconcile jobs whenever attribution or direction changes, and the partial unique index `email_conversion_photo_jobs_active_project_hash_unique (company_id, project_id, source_content_sha256) WHERE operation='materialize'` makes a duplicate active projection structurally impossible. The apply-day sweep revoked 21 mis-attributed jobs (33 → 12 legitimate); revocation hides the mapped photo transactionally and delegates object deletion to the existing retryable cleanup ledger. Source branch: `ops-web` `fix/quoted-email-project-photos-20260811`.

**Trigger reliability repair (2026-08-20; production-applied and runtime-verified 2026-08-21).** Bug `4501a2dc-2b1a-427a-9c8c-04bd6fcdad74` traced recurring attachment-upsert 500s to a PL/pgSQL record/relation alias collision inside `private.reconcile_related_email_conversion_photo_sources`. OPS-Web commit `8c24e50d` and source migration `20260820172857_fix_related_attachment_record_shadowing.sql` replace only that helper, explicitly no-op before a valid lowercase SHA-256 exists, and retain both opportunity and connection/thread sibling matching branches, deterministic order, eligibility semantics, signature, hardened `search_path`, and ACL. A PostgreSQL execution contract runs in CI and covers the original exception, both match branches, exclusion boundaries, invalid hashes, and API-role revocation. The exact SQL is production-live under ledger row `20260821202539_fix_related_attachment_record_shadowing`; independent function/ACL/trigger readback passed at `2026-08-21T20:26:08Z`. The repair is included in OPS-Web `main` commit `6b69551a` and production deployment `dpl_HaQMyTLrfqKZ2tYWD237oZmsJ6vg`. A natural scheduled worker returned HTTP 200 at `2026-08-21T21:03:04Z`, completed three scans, and three canonical descriptors then persisted through the repaired NULL-hash trigger path at `21:04:04Z` without the collision. The later non-NULL hash sibling-matching branch still awaits natural production exposure, and the migration does not backfill descriptors lost before the repair.

**Source attribution (2026-08-17 — partially staged).** Photos this automation publishes were indistinguishable from manual uploads: `complete_email_conversion_photo_job` hardcoded `source = 'other'` on both its insert and its adopt/update path, so nothing recorded that the image arrived by email or who sent it. Three migrations close that gap, deliberately split by risk:

| Migration | Ledger version | State |
|---|---|---|
| `photo_source_email_enum` — adds enum value `'email'` | `20260818053040` | **applied 2026-08-18** |
| `project_photo_email_provenance` — adds `project_photos.email_attachment_id` + `origin_sender_email` + partial index | `20260818053050` | **applied 2026-08-18** |
| `20260817_STAGED_email_photo_source_attribution` — rewrites the completion function to write `source='email'` + provenance, and backfills the 12 already-imported photos | — | **STAGED — NOT APPLIED** |

The first two are pure-additive and invisible to every deployed client (web narrows unknown sources out of its gallery groups; iOS decodes `source` as a plain string). The third is held in `ops-web/supabase/migrations/staged/` until the ops-web `main` push GO, and must be applied **in the same action as the push**: the deployed gallery silently drops photos whose `source` it does not recognise, so flipping the rows before the new bundle is live would hide those 12 photos from the gallery. Until then the pipeline keeps writing `'other'` — current behaviour, no regression.

The staged function reads the sender from the `email_attachments` row it has already loaded and validated (`attachment.from_email`), normalised as `nullif(btrim(coalesce(...,'')),'')`, so a blank sender stores NULL rather than an empty string. Its body is otherwise byte-identical to the live definition.

**Open item before that GO:** the agent readiness RPCs (`read_agent_job_summary_as_system`, `private.read_agent_job_participant_snapshot_v5_impl`, `private.read_agent_job_readiness_issues_v4_impl`) bucket project photos by an exhaustive six-value source list and count anything outside it as `malformed_or_local_count`. They do **not** filter rows out, so nothing disappears — but `deriveSitePhotoReadinessFact` (`ops-web/src/lib/agent-control-plane/services/readiness-rules.ts`) sums only the named buckets into `usable_photo_count`. Once the flip lands, email-sourced photos stop counting toward `SITE_PHOTOS_MISSING`, so a project whose only photos arrived by email would read as having none. Widening those RPCs plus the `ActiveRemotePhotosBySourceSchema` zod shape is the paired fix; it belongs to the agent wave, not to this change.

---

### Automation F: Project Status Cascades

| Trigger | Effect |
|---|---|
| Estimate sent (project linked) | `project.status → Estimated` |
| Estimate approved | `project.status → Accepted` |
| First ProjectTask status → InProgress | `project.status → InProgress` |
| All ProjectTasks status = Completed | `project.status → Completed` (prompt) |
| Invoice status → Paid | `project.status → Closed` |

> **Archived is never a completion outcome.** The paid-invoice cascade above is the ONLY automatic terminal transition for a finished job, and its target is `Closed`, not `Archived`. A job that is complete **and** paid is a *success* → `Closed`. `Archived` is reserved for operator-initiated **pause/cancel**.
>
> **Web correction implemented (2026-07-05, bug `af27ea82` part b; production DB trigger applied 2026-07-08).** The web side honors this table two ways. The paid-invoice database cascade is live in production; the OPS-Web app-layer fallback is staged on local `main` through the held-merge integration and awaits Jackson's customer-facing deploy push:
> 1. **Paid-invoice cascade (primary, source-agnostic).** New DB trigger `trg_close_project_on_full_payment` on `invoices` (function `public.close_project_when_fully_paid()`, migration `ops-web/supabase/migrations/20260705120000_close_project_on_full_payment.sql`) chains off the existing `update_invoice_balance()` payment trigger: when an invoice becomes `paid` and the project's remaining outstanding balance (excluding voided/soft-deleted invoices) reaches 0, a `completed` project advances to `closed`. It lives at the DB layer because customer payments are inserted by four distinct writers (web record-payment modal, Stripe portal webhook, QuickBooks webhook, QuickBooks import) — an app-layer patch would miss three of them. It is best-effort (never aborts the payment transaction), only ever advances `completed`, and never writes `archived`.
> 2. **Agent-queue fallback.** A new `close_project` action type + `executeCloseProject` (`ops-web/src/lib/api/services/approval-queue-service.ts`) writes `status = 'closed'`. The completed-project scan — renamed `ProjectLifecycleService.detectClosableProjects` (was `detectArchivableProjects`, `ops-web/src/lib/api/services/project-lifecycle-service.ts`) — now proposes `close_project` (source id `<projectId>:close`) for any complete + paid project that lingers in `completed`, not `archive_project`. `archive_project`/`executeArchiveProject` are left intact, reserved for the operator pause/cancel path (the workspace `useProjectMutations.archiveProject` flow). iOS already suppresses the misleading `agent_suggestion` rail notification (it has no agent-queue surface).
>
> Production verification (2026-07-08): migration history records `20260708045332 close_project_on_full_payment`; `trg_close_project_on_full_payment` is installed on `public.invoices`; `public.close_project_when_fully_paid()` is `SECURITY DEFINER` with `search_path=public, pg_temp`; no direct PUBLIC/anon/authenticated function grants are present. A rollback sentinel before apply and a rollback sentinel after apply both proved: insert-only paid invoices do not close, partial payment does not close, a final paid invoice closes only a `completed` project, and non-completed projects remain unchanged.
>
> Data audit at implementation time: 0 projects were mis-archived (all `archived` rows are genuine operator pause/cancel); 5 `completed` + fully-paid projects (all in the demo company MAVERICK PROJECTS LTD) were lingering — exactly what the cascade now auto-closes.

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

### Creating a Site Visit (as-built 2026-08-12)

A site visit exists in exactly **two** shapes, separated by one column:

| Shape | `booked_at` | Meaning |
|---|---|---|
| **Walk-up capture (NOW)** | `NULL` | The operator is standing at the door right now. `scheduled_at` defaults to `created_at` and is **junk** — the row is invisible to every scheduling surface. |
| **Booked appointment (BOOK)** | non-null | A real appointment. `scheduled_at` is the start, `duration_minutes` the length, `assignee_ids` who is going. |

`status='scheduled'` means **open**, not booked, and must never be used as the discriminator. See `03_DATA_ARCHITECTURE.md` § 22.

**Entry points (all lead-attached).** Every lead-attached visit affordance presents a two-option branch: **NOW** → the existing immediate capture, unchanged; **BOOK A VISIT** → the booking sheet/modal. On iOS that is the leads-tab VISIT chip, lead detail, the day-sheet panel, and the add-lead sheet; on web it is the pipeline lead detail next-steps strip. The branch is **state-aware**: when the lead already has an open booking, the second option reads `RESCHEDULE — THU 10:30AM` and opens the same sheet in reschedule mode. A second booking is never stacked.

The **FAB stays immediate-capture only**. Booking always has a lead, so booking lives on lead surfaces; the FAB exists for the operator standing at a door. Booking from the calendar or from an empty slot is deliberately out of scope.

**The write path is server-only.** All three surfaces (iOS, web, future MCP tools) call the same RPCs — `book_site_visit`, `reschedule_site_visit`, `cancel_site_visit_booking` (`04_API_AND_INTEGRATION.md` § *Site-visit booking RPCs*). Booking requires connectivity by design: the side effects are server-owned, so there is no offline queueing of a booking — iOS surfaces a terse error instead. Fields are date, time, duration (default 60), WHO'S GOING (defaults to the booker), and a heads-up override defaulting to the user's setting.

**One open booking per lead.** A second booking is rejected only while an existing booked visit is `status='scheduled'`. Once it is `in_progress`, `completed`, or `cancelled` the slot frees — booking a follow-up while on site is legal.

**Side effects of a booking**, all inside the RPC so no caller can diverge:
1. One `activities` row, `type='site_visit_scheduled'` (`Site visit booked` / `rescheduled` / `cancelled`), linked to the visit.
2. A `new_lead` opportunity is nudged to `qualifying` via `move_opportunity_stage` — booking a visit is qualification. Only from `new_lead`.
3. The `trg_site_visits_google_calendar_sync` trigger enqueues outward calendar work (`07_SPECIALIZED_FEATURES.md` § 19c).

**Where a booked visit appears.** Both OPS calendars render booked visits as a **third source** alongside tasks and user events (iOS `CalendarViewModel`; web schedule day/week/month). Visits are explicitly **excluded** from drag-reschedule, cascade, auto-schedule, the unscheduled tray, and crew scheduling — a visit is not a task and must never enter task machinery. They also mirror one-way outward to the operator's personal calendars: Apple via the on-device `CalendarMirrorService` `.siteVisit` source, Google via the queue drain. Editing in Apple or Google does **not** move the OPS booking; reschedules happen in OPS and reconcile outward.

### Checklist Administration

Company checklist managers use `Settings → Operations → Site Visit Types`. They can create a visit type, choose the company default, add/reorder form fields, select each field's input kind, mark it required, and toggle whether it is shown. Built-in types keep their product-owned identity and canonical field kinds, while company choices for visibility, requirement, order, and added fields are preserved across app upgrades. Custom types can be renamed or soft-deleted. All edits apply to future/blank checklists; answered visit records stay unchanged.

The Site Visit type chooser places `EDIT TYPES` immediately after the available type options for users with `settings.company`. Their first Site Visit open also shows a user-scoped pointer to this Settings location with `NOT NOW` and `NEVER SHOW AGAIN`; opening Settings suppresses the guide. Crew without the permission see and use company templates but are never sent into an editor they cannot use.

### Checklist Administration

Company checklist managers use `Settings → Operations → Site Visit Types`. They can create a visit type, choose the company default, add/reorder form fields, select each field's input kind, mark it required, and toggle whether it is shown. Built-in types keep their product-owned identity and canonical field kinds, while company choices for visibility, requirement, order, and added fields are preserved across app upgrades. Custom types can be renamed or soft-deleted. All edits apply to future/blank checklists; answered visit records stay unchanged.

The Site Visit type chooser places `EDIT TYPES` immediately after the available type options for users with `settings.company`. Their first Site Visit open also shows a user-scoped pointer to this Settings location with `NOT NOW` and `NEVER SHOW AGAIN`; opening Settings suppresses the guide. Crew without the permission see and use company templates but are never sent into an editor they cannot use.

### On-Site Experience (Mobile)

**When a booked visit comes due**, prompts arrive in this order (full contract in `07_SPECIALIZED_FEATURES.md` § 14.3.7). All are per-assignee:

1. **Time to leave** — on-device local alert at `scheduled_at − driving ETA − 5 min`. Silently absent without location permission or a lead address; it never prompts for location just for this.
2. **Heads-up push** at `scheduled_at − lead` (per-booking override, else the user's default, else 30 min) — server-fired, so it arrives even if the phone has not synced.
3. **START push** at `scheduled_at`, firing up to 15 minutes late and never after. Tapping it lands directly in the capture view with the lead bound.
4. **START card** in-app from the morning of the visit day, at the top of the day sheet and leads surface. Dismissal is per-visit and kills the card only — never the pushes.

Prompts stop once the visit is no longer `scheduled`. A reschedule re-arms all of them automatically, because the dedupe key carries the appointment epoch.

**The visit itself** (identical for walk-up and booked):
1. Opens the site visit from the START card, a push, the calendar, or the lead
2. Taps "Start Visit" → status → `in_progress`
3. Captures photos (camera or gallery)
4. Fills notes and measurements
5. Taps "Complete Visit" → status → `completed`

Within the primary capture form, section order is always identity → optional
lead summary → checklist → notes. The summary is the trimmed
`opportunities.ai_summary` already present on the currently bound lead, rendered
read-only directly below identity so the operator sees the known job context
before answering fields. Nil/blank summaries are omitted. This surface does not
fetch or edit a summary and does not read `email_threads.ai_summary`, which
remains a separate per-thread artifact. Sources:
`ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift` and
`ops-ios/OPS/Views/SiteVisits/SiteVisitFormSemantics.swift` (code commit
`6fd0ced6`).

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
| `measurement` | LiDAR Dimensioned Photo Capture | During measurement capture |
| `deck_design` | iOS deck builder thumbnail and overlay capture | During deck design work |
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

> **Platform status**: Email integration is implemented on OPS-Web with support for both Gmail and Microsoft 365. API routes under `/api/integrations/email/`, plus a provider abstraction layer, pattern detection engine, AI classification system, webhook-driven sync, and a 5-step "Import Your Pipeline" wizard. iOS does not connect or sync mailboxes and has no full inbox; its one provider-backed exception is the authenticated hold-to-review Due/Overdue follow-up, which delegates all mailbox/thread/template/signature work to OPS-Web. The `email_connections` table (renamed from `gmail_connections`) stores per-connection provider, tokens, sync profile, webhook subscription, and AI feature flags.

### Lead Lifecycle Target Intent

The email pipeline's product contract is: messy email becomes a trustworthy pipeline record. Email threads and activities are the proof trail; the opportunity is the working truth the operator uses to run the lead.

Every linked inbound or outbound email should be evaluated against the opportunity, not only against the provider thread. If the opportunity is missing customer name, company name, phone, email, address/location, scope, estimated value, source/platform, contact relationship, or project context, the lifecycle should fill blank fields as that information becomes available. It must preserve source provenance: thread id, message id, extraction source, confidence, and whether a human confirmed or edited the value.

Core principles:
- **Opportunity is canonical**: `clients`, `sub_clients`, `activities`, `email_threads`, and `opportunity_email_threads` support the opportunity. They should not drift into conflicting truths.
- **Progressive enrichment**: every new linked email can improve the opportunity. Fill blanks and improve weak inferred values; do not silently overwrite operator-entered truth.
- **Opportunity-level staleness**: stale logic runs across all linked threads, known contacts, sub-contacts, spouses/partners, phone/email identities, and related new threads. A new thread from a related contact can reactivate the opportunity.
- **Conservative automation**: automate facts, suggest judgments, and require operator control for destructive or ambiguous actions. If OPS cannot determine the correct action with high confidence, preserve the data and make the state clear.
- **Phase C is optional**: the core lifecycle must remain correct with Phase C off. Phase C improves extraction, matching, drafting, and learning when enabled, but is not required for basic lifecycle correctness.
- **Drafts are auditable**: every draft stores its origin, generated text, final sent text, linked opportunity/thread/message context, edit history, and final disposition.

#### P1-16 Phase C lifecycle convergence (production 2026-08-21)

OPS-Web commits `b293d1dd` through `8c86394e` make meaningful projected
correspondence a durable four-component workload rather than a best-effort
side effect of cursor advancement. Summary, active-stage, commercial, and
event-handoff completion are acknowledged against the exact correspondence
high-water event. A failure retains the marker and its component error for
retry; already committed components are not repeated; a newer event cannot be
cleared by the older lease.

Active-stage changes follow this precedence contract:

1. Record immutable proposed stage, confidence, exact event/message evidence,
   and reason before attempting the change.
2. Recheck expected stage, assignment version, allowed transition, and manual
   evidence boundary under the opportunity row lock.
3. Preserve a human correction against all correspondence at or before its
   captured boundary. Strictly newer correspondence may advance active stages
   such as `quoted → negotiation`; successful Phase C application then clears
   the obsolete manual flag. Terminal manual `lost`, `won`, or `discarded`
   truth is not reopened by this worker.
4. Settle the decision as `applied`, `skipped`, or `review` with the guard
   reason. Replays resolve the existing receipt rather than inventing another
   judgment.

Commercial Won remains deterministic. Complete opportunity-wide evidence is
resolved through exact correspondence events and activities, quoted history is
excluded, and the decisive inbound author must be in the persisted customer
relationship. Clear acceptance records its decision before invoking the
existing guarded opportunity-to-project conversion, which adopts only one
provably unique existing project and otherwise creates exactly one. Ambiguous
identity, sender authority, acceptance, or project adoption records durable
review and leaves stage/project state unchanged.

The same workload can produce a provider-agnostic event envelope only after
distinct authorized parties agree to one resolved event. It never creates an
OPS event, site visit, or provider calendar object. Those apply-time checks and
effects are the P1-17 lifecycle boundary.

Migration `20260820204454_phase_c_lead_intelligence_workload.sql` and its two
foreign-key index follow-ups are applied and verified in production. OPS-Web
commit `6b69551a` is customer-live. Deployment found zero queued workload rows
and did not rewrite an opportunity, project, customer, or appointment as proof.

#### P1-17 confirmed-appointment convergence (production 2026-08-21)

The P1-16 bilateral envelope becomes a booking only through one
server-authoritative consumer. A ready envelope must still identify the exact
company, opportunity, active owner, customer and operator attendees, resolved
timezone, title, location, start/end, `calendar.create` authority, and a
conflict-free slot at apply time. Missing, stale, cancelled, conflicting, or
ambiguous evidence becomes an operator-review outcome; it does not change the
lead or schedule.

The canonical record is a booked `site_visits` row with
`appointment_handoff_id`, `appointment_kind`, `appointment_title`,
`appointment_location`, and the immutable attendee evidence. That preserves
the existing Schedule, assignee, activity, lead-stage, Google queue, and iOS
EventKit behavior instead of introducing a competing event model. The unique
handoff link and leased transaction make duplicate messages, worker retries,
and readback retries converge on the same visit. Provider outages retain the
OPS record and retry the existing provider queue; provider calendar content is
never treated as permission to mutate a lead.

The database migration and OPS-Web consumer are production-live in commit
`6b69551a`. Release readback found zero bilateral handoffs and zero linked site
visits, so no customer or provider-calendar row was changed. The iOS schema
V24/EventKit metadata is merged and pushed on `main` commit `677850ee`; signed
device/App Store distribution remains Jackson's separate release step.

#### Lead intake terminality and reactivation contract (prepared 2026-07-31)

The owner-fenced nonterminal checkpoint is live. Production migration record
`20260805190312_email_provider_snapshot_health`, from repository source
`20260805151056_email_provider_snapshot_health.sql`, makes the 2026-08-05
provider-health split live in the database. Authenticated sync behavior was
runtime-proven on byte-identical repair commit
`146f6d69c4d52d985bc516c0453db6590f92cf97` in deployment
`dpl_6gxJ4P8dv7ohpXpi1wbbdPuyR7FY`, draining the derived queue from seven IDs to
zero. The durable customer release is OPS-Web main commit
`17e70559e5db5d51861e4d8bc8d57b2cd490d10b` in READY deployment
`dpl_AiDK9ZkSfv6BvbP9pSkZiRwnVgSh` as of `2026-08-06T06:29:26.442Z`;
`app.opsapp.co` resolves to that exact SHA with `aliasError = null`. Root/login
returned HTTP 200, the unauthenticated heartbeat
returned the expected HTTP 401, and deployment-scoped logs contained no
error/fatal entry or HTTP 5xx. Current database readback has zero wrapped
continuations, locks, or recovery state, with `last_synced_at`
`2026-08-06T03:57:31.91Z` and `provider_snapshot_at`
`2026-08-06T03:57:32.135712Z`. This exact final deployment was not made to
perform a new authenticated sync or provider/email mutation; behavioral runtime
proof remains the earlier byte-identical deployment. Other prepared reactivation
pieces in this subsection retain their explicitly dated rollout status.

- **Terminal sync authority:** `last_synced_at` means the provider snapshot and
  all bounded derived lead-summary work are complete. A structured Gmail
  cursor, M365 folder/message page remainder, expired-history recovery page,
  pending lead summary, or active sync is end-to-end nonterminal. A
  nonterminal cycle publishes only an owner-fenced `history_id` checkpoint; it
  cannot advance `last_synced_at`. Live `provider_snapshot_at` may advance
  from the database clock when the provider cursor alone is terminal, so
  heartbeat health no longer depends on downstream model completion. Nullable
  rollout rows fall back to `last_synced_at`. The scheduler still bypasses the
  ordinary per-connection interval until the full continuation terminates.
- **Manual contract:** manual sync returns HTTP 200 `complete`, HTTP 202
  `continuing`, or retryable non-2xx `partial`/`failed`. A resolved
  `SyncEngine.runSync` result containing errors is not success.
- **Exact event relationship:** ingestion writes
  `high_confidence_related_contact` only after re-reading the immutable exact
  `(opportunity_id, connection_id, provider_thread_id)` owner. Name similarity
  and locality never grant relationship authority.
- **Transactional archived-lead reactivation:** a new meaningful customer
  inbound whose occurrence is after `archived_at` reactivates an archived,
  active-stage, nondeleted, unmerged, unconverted/project-unlinked opportunity
  in the correspondence insert transaction. It preserves an eligible assignee;
  otherwise it assigns the eligible mailbox intake owner or creates an
  assignment-version-fenced administrator delivery. If no authorized
  recipient exists, the event transaction fails closed. Lost, discarded, won,
  deleted, merged, converted, and project-linked truth is never reopened.
- **Event-by-event evaluation:** an exact related inbound remains the
  reactivation evidence even when a later outbound is the newest meaningful
  event in the same catch-up. Lifecycle execution uses the decision's exact
  event id rather than substituting the batch high-water event.
- **Archive-stage invariant:** active-stage automation returns
  `archived_opportunity` while `archived_at` is nonnull. Reactivation must clear
  that field before stage evaluation can run.
- **Terminal-context drafting:** Phase C performs no autonomous draft, send,
  archive, or follow-up work while the connection is actively syncing or has a
  nonterminal cursor/recovery page. The thread remains dirty for the terminal
  retry. Draft greeting identity comes from the exact latest inbound source
  sender, not another participant or a similar contact name.
- **Stale draft reconciliation:** `ai_draft_history.source_message_id` is the
  immutable reply boundary. Any later persisted inbound or outbound on the
  exact thread makes that provider draft stale; the normal mailbox worker
  deletes it idempotently, marks its history `superseded`, and applies no
  sent/edit learning.
- **No conversion inference:** reactivation and drafting cannot create a
  project. Project creation still requires decisive commercial acceptance plus
  property-level address proof.

#### P1 Provider ID Guardrails

As of Lead Lifecycle P1, provider-backed email lifecycle writes must reject blank provider identifiers before creating any new activity, `email_threads` cache row, `opportunity_email_threads` link, or correspondence-count update.

Required behavior:
- Provider-backed sync/send/backfill paths require a nonblank provider thread id and nonblank provider message id.
- Import wizard leads must carry every exact provider message id, raw provider thread id, occurrence time, and persisted direction observed during full-thread analysis. Ordinary imports without that exact set stop before CRM writes and require mailbox reanalysis; they never create an ambiguous synthetic thread shell. One activity/event is written per provider message, and every ordinary raw thread receives an `opportunity_email_threads` link. Message-scoped contact-form submissions deliberately do not inherit/link the reused platform thread, because one provider thread may contain unrelated customers.
- Rejected provider-backed emails create no lifecycle writes, log a structured server warning, and increment sync diagnostics. The cycle fails closed and leaves the provider cursor unchanged so the message can be repaired/replayed; it is never silently skipped as though ingestion completed.
- The contact-form parsed sender identity must remain consistent across matching, activity creation, and thread-cache writes for newly processed provider-backed emails.
- Existing bad rows are report-only until an operator approves cleanup. The P1 dry-run artifact lives at `docs/data-cleanup/lead-lifecycle-p1-bad-thread-dry-run-2026-05-26.md`.

#### P2 Canonical Enrichment

As of Lead Lifecycle P2, email ingestion performs conservative canonical enrichment after provider ID validation. Inbound sync, sent-folder safety-net sync, import wizard leads, and historical Gmail import can fill missing opportunity/client fields from deterministic facts that are already present in the email or reviewed import payload.

Allowed P2 writeback targets:
- `opportunities.contact_name`, `contact_email`, `contact_phone`
- `opportunities.address`
- `opportunities.estimated_value` and `detected_value`
- `opportunities.description`
- `opportunities.source` (`email` for email pipeline ingestion)
- `opportunities.source_email_id` (provider thread id)
- `clients.name`, `email`, `phone_number`, `address`

P2 writes only blanks or clearly weak placeholders such as empty values, unknown/new-lead markers, raw email-address names, zero estimated values, and known platform/system email addresses. It must not overwrite operator-entered client or opportunity values. Contact-form submitter identity remains preferred over the platform sender; platform sender emails such as Wix, HomeStars, or website form notifications are not written as customer email addresses. Canonical enrichment is company-scoped on every opportunity/client read and write, and the opportunity's stored `client_id` is authoritative; an explicit caller client that disagrees is rejected. Exact-email fallback matching escapes SQL `ILIKE` wildcards before querying and any lookup failure stops the lifecycle write.

The AI classifier cannot author customer identity. Deterministic sender/recipient/form facts establish the candidate name, email, phone, address, and client relationship. AI output may classify lead/business/noise, select a valid stage, and fill a previously missing estimate or description, but returned identity fields never replace deterministic facts. Transport, parse, partial-result, duplicate-result, unknown-result, and missing-result failures stop the sync cycle before its provider cursor advances. A valid lead is not discarded merely because the model omits its optional client object.

Existing provenance support:
- `activities.email_thread_id`, `activities.email_message_id`, and `activities.email_connection_id` preserve provider thread/message/mailbox proof for actual email activities. Provider-message uniqueness is scoped to `(company_id, email_connection_id, email_message_id)`, not globally.
- `opportunity_email_threads.thread_id` + `connection_id` preserve the opportunity-to-provider-thread link.
- `email_threads.provider_thread_id` preserves the inbox cache provider thread id.
- `opportunities.source_email_id` can hold the provider thread id for the lead source.
- `opportunities.source_thread_key` stores the connection-scoped logical ingestion identity. Ordinary correspondence uses `email:<provider>:<connection_id>:thread:<provider_thread_id>`; known contact-form notifications use `email:<provider>:<connection_id>:message:<provider_message_id>` so separate submissions cannot inherit one another merely because Gmail or the form platform reused a thread.
- `lead_field_provenance` records canonical field names (`title`, `contact_name`, `contact_email`, `contact_phone`, `contact_address`, and other enriched opportunity facts), the constrained source class (`operator`, `ai`, `contact_form`, `inbound`, `outbound`, `import`, or `merge`), confidence, provider thread/message proof, and confirmation metadata. Provenance participates in survivorship: stronger verified evidence may replace weaker same-identity machine inference only while the stored value still matches its snapshot; operator-confirmed values remain protected. Contact names bind to an exact normalized customer email before stronger evidence may replace them. An exact linked-client directory name may propagate to the opportunity at `merge` confidence `0.90` only when the linked client, opportunity, and current correspondence share that email. A full name extracted after an explicit authored sign-off carries inbound confidence `0.92`; it outranks that directory evidence and may promote a weaker header/local-part name for the same sender without raising the confidence of unrelated phone, address, value, or description facts. Generated email opportunity titles carry their own snapshots and follow the promoted name only while OPS ownership is still provable.

Current schema gaps for full provenance and company/source detail:
- No `clients.company_name` or `opportunities.company_name` column exists. Company name can only fill weak `clients.name` values when that is safe.
- No `opportunities.source_platform` / `source_platform_label` column exists for HomeStars, Wix, website form, or other lead platform names.
- No provider message id column exists on `opportunities`; message-level proof lives on `activities.email_message_id`.
- No explicit contact relationship column exists on opportunities for spouse/PM/site-super relationships; `sub_clients.title` can hold that relationship only after a sub-client exists.

#### P3 Opportunity Relationship Matching

As of Lead Lifecycle P3, provider thread id is no longer the only lifecycle unit. New provider threads are evaluated against existing opportunities before OPS creates a cold duplicate. The matching boundary is the opportunity: once a new thread is deterministically linked, `opportunity_email_threads` receives the new `(thread_id, connection_id)` link, the inbound activity attaches to the winning opportunity, correspondence counters update there, and P2 enrichment runs against that same winning opportunity without overwriting operator-entered canonical values.

P3 deterministic gates:
- **Existing provider thread link**: for ordinary correspondence, if `(thread_id, connection_id)` is already linked, use that opportunity deterministically. Parsed contact-form submissions are message-scoped and bypass this gate; the raw thread remains on their activities for mailbox proof but never becomes a one-thread/one-opportunity inheritance link. Ownership is first-writer immutable: every application writer inserts if absent, reads back the canonical owner, and never updates it to a competing opportunity. The expand-phase database trigger rejects both cross-company connection/opportunity links and any `opportunity_id` rewrite, including writes from an older application instance during rolling deploy. Manual send preflights a caller-supplied thread before the irreversible provider send. If a verified same-company owner still wins while the provider request is in flight, the already-sent message is recorded against that canonical owner and reported successful; it is never returned as a retryable send failure that could duplicate customer email. Activity, correspondence event/projection, inbox cache, and lifecycle writes all use that same owner.
- **Exact known contact**: exact `clients.email`, `sub_clients.email`, or `opportunities.contact_email` can link to an existing active opportunity.
- **Existing related contact**: an exact sub-client email relationship links to the parent client's active opportunity.
- **Exact phone**: exact normalized phone match across opportunity/client/sub-client facts can link when the opportunity is active or the linked project is active.
- **Same property, same active job**: only an exact property-qualified address can link when the opportunity is active (`new_lead`, `qualifying`, `quoting`, `quoted`, `follow_up`, `negotiation`) or a linked project is active (`rfq`, `estimated`, `accepted`, `in_progress`). A city, municipality, neighbourhood, region, postal locality, or area label is contextual metadata only and never enters an address identity set. Ordinary civic qualification requires a bounded street number, street name, and recognized street-type suffix; a number plus locality or a suffix-less label is not property evidence. Supported highway/range-road, rural-route/site/box, lot/concession or lot/block/plan, and explicit parcel/PID identities also qualify. Unit identifiers are preserved case-insensitively so two units at one building do not collapse.
- **Quoted prior-thread scope**: deterministic scope overlap can support a link only when it overlaps known prior opportunity/project text and the candidate is active. This is a strict enhancer, not a freeform guess.

P3 non-linking rules:
- Do not infer spouse, partner, property manager, or site-super relationships from first name or last name alone.
- Do not treat platform senders such as Wix, HomeStars, or website form notification mailboxes as customer identity. Parsed submitter identity wins.
- Do not blindly attach new work to terminal opportunities (`won`, `lost`, `discarded`, and future terminal values such as `merged`, `converted`, or `disqualified`) or archived opportunities.
- If the same customer/property has only a completed, closed, or archived prior project and the incoming scope is distinct, create a separate opportunity.
- If confidence is below the deterministic threshold, create a separate lead and preserve merge evidence through activity/thread/source fields rather than over-linking.

Phase C boundary:
- Phase C may improve extraction quality, relationship suggestions, and future household/project graph confidence.
- Phase C must not be required for P3. With Phase C off, exact contact, exact phone, exact property-qualified address, active opportunity state, and active project state still drive deterministic matching.
- Phase C must not perform destructive merge, stale/archive/lost automation, or project conversion as part of P3. Those remain later lifecycle phases and operator-controlled flows.

Known P3 schema gaps:
- There is still no durable field-level provenance table for why a thread was linked to an opportunity. Current proof is spread across `opportunity_email_threads`, `activities`, `source_email_id`, and server logs/tests.
- There is no explicit `opportunity_relationship_matches` or merge-candidate table to persist low-confidence duplicate/future-merge suggestions.
- There is no canonical relationship type column for spouse/partner/property-manager/site-super identity unless the contact is represented as a `sub_clients` row.
- There is no structured scope signature column for comparing "same address, new job" versus "same address, same job"; P3 uses conservative deterministic text/address/status gates only.

#### P4 Schema Foundation and Dry-Run Evaluator

As of Lead Lifecycle P4-2, stale/follow-up evaluation has a first-class schema and deterministic dry-run evaluator. P4-2 is still non-destructive: it may create lifecycle proof rows at safe app-code boundaries and may produce read-only dry-run artifacts, but it must not archive opportunities, mark opportunities lost, create provider drafts in production, or send email.

P4 schema contract:
- `opportunity_correspondence_events` stores opportunity-level correspondence proof. It links to company, opportunity, optional activity, optional email connection, provider thread id, optional provider message id, direction (`inbound`/`outbound`), party role (`customer`, `ops`, `internal`, `provider`, `system`, `marketing`, `unknown`), `is_meaningful`, `noise_reason`, occurrence time, optional linked contact reference, source boundary, subject, sender, recipients, and CCs. A partial unique index protects provider message id duplication per company/connection.
- `opportunity_follow_up_drafts` stores auditable lifecycle drafts. It links to company, opportunity, optional connection/thread, optional source correspondence event, origin (`operator`, `template_follow_up`, `phase_c`, `system_handoff`), sequence number, subject, original generated body, current body, final sent body, status (`drafted`, `sent`, `discarded`, `superseded`, `archived`), optional provider draft id, optional `ai_draft_history` id, editors, and lifecycle timestamps. At most one open `template_follow_up` draft exists per opportunity.
- `opportunity_lifecycle_state` stores the opportunity's P4 stale state: last meaningful event/time/direction, unanswered follow-up count, second follow-up sent time, operator follow-up miss time, stale status, protected-until timestamp, and update time.
- `opportunity_lifecycle_action_audit` stores guarded P4 action attempts/results once the P4-12 additive migration is applied. It records company, opportunity, action, approved action key, execution mode, status, guard reason, server-computed before/after values, decision reason/evidence, approval metadata, run id, error code/message provenance, runner, and creation time. A partial unique index prevents duplicate applied rows for the same approved company/opportunity/action/key.
- `lead_lifecycle_settings` stores company-level cadence and template settings. Defaults are 7 days to draft a follow-up after OPS outbound, 7 days to archive after the second unanswered follow-up, 14 days to archive when no meaningful correspondence exists, 30 days to mark beyond-qualified operator no-response as lost, default template subject `Following up`, and default template body `Hi {{first_name}}, just checking in to see if you had any questions about the quote. No pressure — I wanted to make sure you had everything you needed.`

P4 deterministic classifier rules:
- Customer inbound counts as meaningful only when the sender or parsed contact-form submitter is a real external customer/contact. Parsed submitter identity wins over platform sender identity.
- OPS outbound counts as meaningful only when a real OPS account/connection sends to an external customer/contact.
- Active OPS staff identity is authoritative only from an exact registered user email or an exact active `user_email_aliases.status='verified'` row. A signature that exactly matches one active teammate's full roster name and full normalized phone may create/update a pending alias candidate and force review, but it never grants staff identity by itself. Once the exact mailbox is pending, later messages remain quarantined as outbound/review without requiring the signature to repeat; rejection releases that exact mailbox back to ordinary external-sender handling. A registered teammate address in To/CC is corroborating evidence only. Name similarity, phone fragments, public-domain similarity, and private-domain guesses never establish an alias. Once a verified alias resolves the sender, ingestion and recovery classify the message as outbound/internal before lead matching, while exact external recipients remain eligible customer identities. Alias evidence and final review authority are administrator-only; final decisions are immutable and rejected decisions never claim verification.
- Provider/platform senders, automated bounces, internal-only/system messages, duplicate provider message ids, and marketing/promotional messages are not meaningful. They are retained as proof rows with `is_meaningful=false` and a `noise_reason`.
- Blank provider thread ids are never meaningful. Provider-backed lifecycle writes still follow the P1 provider-id guardrails before creating P4 events.
- Platform senders such as website form notification mailboxes are never treated as the customer. They can support source/provenance only.

P4 evaluator dry-run behavior:
- Input is an opportunity, optional `opportunity_lifecycle_state`, meaningful correspondence events, settings, and evaluator clock.
- Output is one dry-run decision: `create_follow_up_draft`, `archive_after_two_unanswered_followups`, `archive_no_meaningful_correspondence`, `operator_follow_up_miss`, `move_to_lost_operator_no_response`, `reactivate_on_related_inbound`, or `no_action`.
- Won, lost, discarded, deleted, converted/project-linked, archived, and future terminal/protected opportunities are ignored for stale monitoring. `reactivate_on_related_inbound` is an event-triggered decision only when a new related meaningful inbound arrives; P4 sweeps do not keep monitoring archived opportunities.
- Last meaningful OPS outbound past the configured threshold returns `create_follow_up_draft`. P4-2 does not create or send that draft in production.
- Two tracked unanswered OPS follow-ups past the configured second-follow-up archive threshold returns `archive_after_two_unanswered_followups`. P4-2 does not execute archive.
- No meaningful correspondence past the configured no-correspondence threshold returns `archive_no_meaningful_correspondence`. P4-2 does not execute archive.
- Last meaningful inbound with no later OPS reply returns `operator_follow_up_miss`; if it is beyond the lost threshold and the opportunity is beyond qualified (`quoting`, `quoted`, `follow_up`, `negotiation`), it returns `move_to_lost_operator_no_response`. P4-2 does not execute lost mutations.

Safe P4-2 write boundaries:
- Inbound/outbound sync may create `opportunity_correspondence_events` after provider thread/message ids validate, P3 relationship matching selects the opportunity, and P2 fill-only enrichment remains intact. When the event is meaningful, P4-2 app code may also upsert `opportunity_lifecycle_state` for that opportunity: last meaningful event id/time/direction, clear stale status fields, and reset unanswered follow-up counters for meaningful inbound.
- Email send may create an outbound meaningful correspondence event after the provider returns valid thread/message ids, then upsert `opportunity_lifecycle_state` with the outbound meaningful event when it is the newest meaningful correspondence.
- Import/historical import may create correspondence events only where provider ids satisfy the explicit import boundary. Invalid provider ids create no P4 event and no lifecycle-state upsert.
- P4-2 dry-run scripts are read-only against Supabase and write only a markdown artifact under `docs/data-cleanup/`.
- P4-2 does not execute archive, lost, or reactivation mutations. Those action-execution paths remain P4-3+ only, behind guarded write paths, idempotency, audit, and operator-visible review.

P4-8 non-destructive action-execution boundary:
- P4-8 may execute only non-destructive decisions from the P4 evaluator. `create_follow_up_draft` creates a local `opportunity_follow_up_drafts` row with `origin = 'template_follow_up'`, `status = 'drafted'`, the next template sequence number from stored lifecycle state/prior sent template follow-ups, rendered template subject/body, the triggering `source_event_id`, and optional connection/provider thread context. It does not create a Gmail/M365 provider draft and does not auto-send.
- Template follow-up execution is idempotent. The open-template unique contract remains one open `template_follow_up` draft per opportunity. Existing operator, provider-backed, Phase C, or system-handoff drafts are not overwritten, discarded, or reused by P4-8.
- `operator_follow_up_miss` creates a persistent operator rail notification through the existing notifications table. OPS currently has no dedicated lead-lifecycle notification type, so P4-8 uses the compatible `leads_waiting` type and deterministic title/action URL dedupe. Notifications must route to usable internal OPS pages: provider thread ids are resolved to internal `email_threads.id` before `/inbox/{threadId}` is stored, and missing/synthetic/legacy thread contexts fall back to `/pipeline?opportunityId={opportunity_id}`.
- Non-destructive actions update `opportunity_lifecycle_state` without pretending an email was sent. Template draft creation uses the live constraint-compatible stale status `follow_up_draft_due` and must persist required lifecycle state before inserting the local draft row, so a failed state update cannot leave a new template draft without the required state. Operator misses set `operator_follow_up_miss_at` and stale status to `operator_follow_up_miss`. Neither path mutates canonical `opportunities.stage`, `archived_at`, `lost_reason`, `project_id`, or project links.
- Meaningful inbound handling clears stale status fields, resets unanswered follow-up counters, clears operator miss state, and supersedes stale open `template_follow_up` draft rows for that opportunity. Manual/operator, provider, Phase C, and system handoff drafts stay intact.
- P4-8 dry-run/apply tooling defaults to dry-run and writes only a markdown artifact unless an explicit non-destructive apply flag is passed after approval. The artifact must count candidates, drafts to create, notifications to create, lifecycle states to update, drafts to supersede, already-existing skips, and destructive-action skips.
- Archive, lost, and reactivation decisions remain skipped in P4-8. Archive/lost execution and related-inbound unarchive/reactivation remain P4-10+ product work behind separate approval, guarded write paths, idempotency, audit, and focused tests.
- P4-8 must not auto-send email, create provider drafts, depend on Phase C, or start P5/P6.

P4-12 guarded destructive action-execution boundary:
- P4-12 may execute only the remaining reviewed P4 evaluator decisions: `archive_after_two_unanswered_followups`, `archive_no_meaningful_correspondence`, `move_to_lost_operator_no_response`, and `reactivate_on_related_inbound`. Production execution is blocked unless a dry-run artifact has been reviewed and an exact opportunity/action approval list is supplied to apply mode.
- The production script remains dry-run by default and writes only a markdown artifact under `/Users/jacksonsweet/Projects/OPS/docs/data-cleanup/`. Apply mode requires `--apply-guarded-p4-actions --approved-actions-file <json>` and refuses to run until `opportunity_lifecycle_action_audit` exists in the target schema.
- Archive execution is reversible and may set only `opportunities.archived_at`. It must not manually set `updated_at` and must not change stage, lost fields, project links, correspondence rows, drafts, notifications, or provider state.
- Operator no-response lost execution is allowed only for beyond-qualified stages (`quoting`, `quoted`, `follow_up`, `negotiation`). It must skip `new_lead`, `qualifying`, won, lost, discarded, deleted, converted, and project-linked opportunities. The only allowed opportunity changes are `stage = 'lost'`, `lost_reason = 'operator_no_response'`, `lost_notes`, and `actual_close_date`; it must not manually set `updated_at`.
- Related-inbound reactivation may clear only `opportunities.archived_at`. It must skip won, lost, discarded, deleted, converted/project-linked opportunities and any archived opportunity whose latest meaningful inbound is not from a related/high-confidence related contact. It does not reopen lost/discarded records and does not change stage.
- Guarded execution is idempotent. Already archived rows, already applied approval keys, disallowed stages, deleted rows, converted/project-linked rows, missing related inbound, and current-evaluator mismatches are skipped and reported. Repeated apply must not duplicate local drafts, notifications, provider drafts, sent email, or opportunity state transitions.
- Each applied archive/lost/reactivation runs through `public.execute_opportunity_lifecycle_guarded_action(...)`, which writes the audit row and the opportunity mutation in one database transaction. This RPC is a service-role/server-only boundary for trusted OPS server code; ordinary authenticated users must not receive `EXECUTE` and must not call it directly through PostgREST. RLS/company checks remain defense in depth, not the approval gate.
- The guarded RPC computes audit `before_values` from the locked live `opportunities` row and computes audit `after_values` from the exact mutation variables it applies. Client payloads may supply expected before/after values for optimistic verification only; they are not the stored audit source of truth. If expected guard/audit values disagree with the live row or the server-computed mutation, the RPC records a guarded skip such as `snapshot_mismatch` and does not report archive/lost/reactivation as applied. The exact audited mutation fields are `archived_at` for archive, `stage`/`lost_reason`/`lost_notes`/`actual_close_date` for lost, and `archived_at` for reactivation. The existing `opportunity_lifecycle_state` table is not sufficient for this audit because it has stale status fields but no action key, mode, guard reason, before/after snapshot, provenance/error fields, or applied-result record.
- P4-12 does not send email, does not create provider drafts, does not call provider send APIs, does not mutate historical data outside the exact approved action set, and does not start P5/P6.

P4-22 legacy correspondence proof boundary:
- Destructive dry-runs against historical opportunities must not treat an empty `opportunity_correspondence_events` table as proof of no meaningful correspondence. The P4 proof tables were introduced after many legacy opportunities already had real customer replies, form submissions, RFQs, site visits, calls, outbound quotes, and follow-ups recorded elsewhere.
- Before any destructive dry-run is eligible for review, legacy opportunities require either a legacy correspondence proof backfill dry-run or a deterministic legacy-evidence adapter. Valid sources are existing `activities`, `email_threads`, `opportunity_email_threads`, provider thread/message ids, `email_connections` sender context, and deterministic opportunity source/title fallback when no activity row exists. The adapter must remain opportunity-scoped; it must not reuse evidence across P3 relationship boundaries or reinterpret a provider thread linked to a different opportunity.
- Backfill planning must be idempotent by provider message id when available, by activity id for legacy activity evidence, and by opportunity id for deterministic opportunity-source fallback. It must not create duplicate meaningful events, and provider-backed rows with blank or invalid provider thread ids remain blocked by the P1 provider-id guardrails. Non-provider legacy evidence may be represented with an explicit legacy source boundary, but it must be labeled as activity/opportunity-scoped rather than provider-backed.
- Provider-backed legacy activity is not sufficient by itself when a linked `email_threads` row has usable latest-message truth. Activity rows without `provider_message_id` are treated as thread-level legacy summaries and must reconcile to the linked thread's latest direction, timestamp, sender/recipient, and party classification. Message-specific activity evidence may coexist with a later linked thread summary so stale/lost decisions use the latest reconciled opportunity truth instead of activity `direction` alone.
- Meaningful legacy inclusion is limited to deterministic customer form submissions, real customer replies, OPS outbound quote/follow-up messages, calls, RFQs, site visits, and meetings. Provider/platform noise, internal/system-only messages, automated bounces, marketing/promotional mail, duplicate provider messages, platform sender identity masquerading as a customer, and ambiguous evidence must be skipped with a reason.
- Forwarded contact-form threads are meaningful only when the adapter can prove a non-internal submitter from parsed form content or an external participant on the linked thread. Internal-only forwarded form shells without submitter or external-contact proof remain ambiguous and must be skipped.
- Guarded archive/lost dry-runs must not promote an opportunity to mutation output when the same opportunity has unresolved legacy evidence (`ambiguous_legacy_evidence`, `relationship_mismatch`, `missing_provider_id`, or `missing_created_at`). Those rows prove the evaluator does not have clean correspondence truth yet, so they must appear in a blocked/skipped section rather than in the approval JSON.
- A legacy backfill dry-run must render the exact `opportunity_correspondence_events` rows that would be inserted and the exact `opportunity_lifecycle_state` rows that would be upserted, including source boundary, confidence, reason, provider ids or legacy synthetic boundary, activity id, opportunity id, direction, party role, meaningful flag, and occurrence time. It must also prove that `opportunities`, P4 proof/state/settings tables, audit tables, guarded RPCs, drafts, notifications, provider drafts, and email sending were not mutated.
- A guarded-action dry-run artifact must render exact projected audit rows, not only `would_record` markers or an approval JSON block. Each projected row must include company id, opportunity id, action, approved action key placeholder, execution mode, status, guard reason, before values, after values, decision reason/evidence, approval metadata placeholders, run id, error fields, runner, and a clear `dry_run_projection_not_approved` marker. Dry-run projected audit rows are not approval and must not imply that apply mode is authorized.

Pending-projection guard boundary (bounded 2026-07-22):
- **Root cause (established 2026-07-22).** An unresolved duplicate-lead pair left one Gmail thread with split ownership — the `email_threads` cache row was owned by one lead while the delivered activities routed to its duplicate. The thread-parent conflict introduced with canonical-parent enforcement therefore threw from `EmailThreadService.upsertFromEmail` on every cycle; because the correspondence event insert and its counter projection were two separate PostgREST transactions, the throw landed after the event had committed with `opportunity_projection_applied = false` and before the projection ran, and the hourly replay repeated the identical failure (the dedupe path refreshes thread state before repairing projection). That stranded one pending row and froze the mailbox cursor for 20+ hours; the then-unbounded pending guard escalated the single stranded row into the platform-wide 40001 retry storm.
- **Atomic write path — the primary fix (migration `20260722210000_atomic_correspondence_event_projection`).** `record_opportunity_correspondence_event(...)` inserts the correspondence event AND projects its opportunity counters in ONE transaction under the opportunity row lock, so `opportunity_projection_applied` is inserted true and a durable-but-unprojected row can no longer occur on any write path — sync ingestion, historical/email imports, and email-send / approved-action reconciliation all funnel through it. `opportunity_projection_applied = false` can now only describe rows written before this RPC existed. The 60-second-bounded guard below and the legacy `apply_opportunity_correspondence_event` RPC remain in place only as backstops for those pre-existing rows and for idempotent re-projection on replay. Commercial RPCs serialize against ingestion via the same opportunity lock the RPC takes, not a two-step write.
- `private.opportunity_has_pending_meaningful_email(company_id, opportunity_id)` is the shared guard over that invariant. The four guarded commercial RPCs — `convert_opportunity_to_project` (actorless path), `commit_lead_summary_snapshot`, `apply_email_opportunity_deferred_disposition`, and `apply_email_opportunity_declined_disposition` — call it under the opportunity lock and raise `meaningful correspondence projection pending` with SQLSTATE 40001 while it returns true, so no commercial outcome can be decided against an incomplete conversation. With the atomic write path in place no new write can strand a pending row, so in steady state this guard is a legacy backstop that returns false.
- **Decisive customer rejection (live 2026-07-29; migration `20260728162000_guarded_customer_decline_lifecycle`, ops-web `d24b41f7`).** An unambiguous inbound customer rejection now maps deterministically to Lost. Choosing another provider for financial reasons records `reason_code=price`; an unequivocal rejection without a supported reason records `customer_declined`. Temporary budget or timing deferral remains deferred and does not become Lost. `apply_email_opportunity_declined_disposition` is service-role-only and proves the active mailbox, persisted customer sender, exact provider message, meaningful projected correspondence, evaluated event high-water mark, stage snapshot, and assignment version under one opportunity lock. It protects Won/discarded and every manual terminal decision. A nonterminal manual flag may represent a historical repair, so newer decisive customer evidence may close that lead and clears the manual flag; a newer engine-owned guarded Lost disposition may be superseded only by strictly newer decisive evidence. Stale/out-of-order evidence raises a serialization error, exact replay returns `already_applied`, and stage/disposition/transition writes are atomic. The summary refresh follows the committed business state and renders no follow-up action for Lost.
- **Staff-authored false-lead correction (live and executed 2026-07-29; migrations `20260728163000_guarded_staff_false_lead_correction`, `20260729173000_fix_staff_false_lead_notification_company_cast`, and `20260729174500_preserve_referenced_staff_false_lead_client`).** `apply_staff_authored_false_lead_correction_guarded(...)` is the only permitted historical write path for the verified two-message Jason alias incident. It takes a content-addressed manifest and exact expected-row specification, then fails closed on any mailbox, roster, alias, opportunity, customer, event, activity, thread, attachment, lifecycle, notification, assignment, draft, or provenance drift. The exact secondary address becomes a verified alias for the exact active teammate; no name/domain/location inference is used. The external recipient at the property-qualified quote address receives a new client/lead with a message-scoped source key and canonical company-mailbox assignment; the other external recipient's historical message moves to her existing Won project lead while every terminal/project/assignment field remains unchanged. Both messages become outbound OPS correspondence, canonical thread/cache ownership moves with them, and attachment attribution is requeued with a generation proof. The false generated draft is discarded only in OPS—the RPC records `provider_mutations_disabled=true` and never edits Gmail. False notifications are resolved and the false lead is dispositioned/discarded and soft-deleted. A schema-wide reference count deletes the source client only when unused; otherwise the shared client remains active and the receipt records the exact remaining count. `lead_intake_correction_runs` records one immutable result; an exact retry returns that result and a changed retry raises a conflict.
- The guard is time-bounded: only unprojected meaningful events younger than 60 seconds count as pending (migration `20260722150000_bound_meaningful_email_projection_pending_guard`). The 2026-07-22 full outage proved the unbounded form fails closed forever — one permanently stuck row made all three RPCs raise 40001 on every call, and zero-backoff worker retries (~1,800 failed transactions/sec) pinned database CPU and took the API down. Past 60 seconds a stuck row degrades into silent evidence exclusion on that one lead, surfaced by monitoring, instead of a platform-wide write freeze.
- Worker 40001 policy: a serialization failure is retried only through `withSerializationRetry` (`ops-web/src/lib/supabase/serialization-retry.ts`) — equal-jitter exponential backoff from a 250ms base doubling to a 30s ceiling, five attempts, then a typed `SerializationRetryExhaustedError` that is recorded and parked, never re-looped. The sync engine retries the whole acceptance evaluation (never a bare RPC replay) so each attempt re-derives its evidence high-water mark; the lead-summary path retries only the snapshot commit, never model generation. One wedged opportunity cannot starve its batch: the sync accept loop evaluates every other lead first, then holds the provider cursor with one aggregated persistence error, which self-heals within a cycle because of the 60-second guard bound.
- **Thread-parent conflicts quarantine per-thread and never block ingestion (2026-07-22).** When `upsertFromEmail` hits a canonical-parent conflict — two leads claiming one conversation — `EmailThreadService` throws a typed `EmailThreadParentConflictError` and `sync-engine`'s `persistDeterministicEmailThreadState` catches it: it logs the conflict (connection, provider thread, both lead ids), raises one persistent operator-rail alert (`system_alert`, deduped on `email-thread-parent-conflict:{connectionId}:{providerThreadId}`, deep-linking to `/pipeline`), and returns without rethrowing. The message's projection and the provider cursor proceed; the thread cache simply stops refreshing until an operator merges the duplicate leads. Every other `upsertFromEmail` call site (unmatched-inbound, exact-recovery, and the send / approved-action reconciliation services) keeps its strict throw — the quarantine is scoped to deterministic sync thread-state refresh only.
- Monitoring + auto-repair: `/api/cron/email/projection-stuck-check` runs every 5 minutes, 24/7. Before alerting it now auto-repairs each stuck row that carries a connection id and provider message id by calling the idempotent `apply_opportunity_correspondence_event` RPC (capped at 50 repairs per run, inside the 60s function budget); rows that self-heal drop out of the stuck set. If every stuck row clears, the run resolves any open alert and re-arms. Only rows that cannot be repaired — or that lack a connection/message id — reach the persistent operator-rail alert (deduped on `email-correspondence-projection-stuck`, auto-resolved on recovery), whose body now also names how many were auto-repaired this run. The alert condition — `is_meaningful AND NOT opportunity_projection_applied AND created_at < now() - interval '5 minutes'` — preceded the 2026-07-22 outage by 18 hours. A firing alert means a projection fault needs root-causing and the affected leads' evidence needs repair; it never blocks writes by itself.

P4-30/P4-31 production closeout:
- On 2026-05-29, the guarded action audit/RPC migration was live in production and the legacy correspondence proof backfill was applied for existing historical evidence. The backfill wrote only `opportunity_correspondence_events` and `opportunity_lifecycle_state`; it did not mutate `opportunities`, clients, activities, email threads, drafts, notifications, provider state, or email sending.
- The reviewed backfill wrote 329 correspondence events and upserted 184 lifecycle state rows. The immediate post-apply dry-run planned zero additional backfill rows, which is the expected idempotency proof for the historical set at that moment.
- After backfill, the guarded destructive dry-run had one evidence-supported candidate: opportunity `d2000000-0000-4000-d200-000000000009` with action `move_to_lost_operator_no_response`. The apply used the guarded RPC and exact approved action key for that one row only. The opportunity changed from `negotiation` to `lost`, with `lost_reason = 'operator_no_response'`, guarded lost notes, and `actual_close_date = '2026-05-29'`. No archive or reactivation action ran.
- The corresponding `opportunity_lifecycle_action_audit` row id is `d2bd5696-8ab7-4009-9df4-6fe85e4dc31a`, status `applied`, key `d2000000-0000-4000-d200-000000000009:move_to_lost_operator_no_response:2026-05-28`. Server-computed before/after values matched the actual opportunity mutation.
- The immediate post-apply guarded dry-run returned zero destructive candidates, zero opportunity rows to mutate, and zero audit rows to record. This closes the P4 stale/lifecycle execution path for the then-current dataset; future P4 executions must still run through fresh dry-run artifacts, exact approval rows, and the guarded RPC.

P5-1 local operator follow-up workflow:
- On 2026-05-29, P5-1 used the populated P4 proof/state tables to create local, auditable operator workflow only. It did not send email, create Gmail/Microsoft provider drafts, archive opportunities, mark opportunities lost, reactivate opportunities, mutate clients/activities/email threads, or run guarded destructive apply.
- `lead_lifecycle_settings` remains the source of company cadence and template defaults. If a company has eligible P5 candidates but no settings row, P5-1 may insert the default settings row idempotently before action execution. The current default follow-up cadence is 7 days after the last meaningful OPS outbound, the default follow-up subject is `Following up`, and the default template body is `Hi {{first_name}}, just checking in to see if you had any questions about the quote. No pressure — I wanted to make sure you had everything you needed.` Migration `20260723233000_operator_one_tap_lead_follow_up.sql` upgrades only rows still equal to the prior stock body; custom company templates are preserved.
- `create_follow_up_draft` creates a local `opportunity_follow_up_drafts` row with `origin = 'template_follow_up'`, `status = 'drafted'`, rendered subject/body, optional source event, and optional provider thread context. `provider_draft_id` stays null. The database unique contract remains one open `template_follow_up` draft per company/opportunity.
- Template follow-up execution must not overwrite, discard, reuse, or supersede operator, Phase C, system-handoff, provider-backed, or sent drafts. Meaningful inbound may supersede only stale open `template_follow_up` drafts for the same opportunity.
- Lifecycle state must persist before a template draft insert. `create_follow_up_draft` sets stale status `follow_up_draft_due`; `operator_follow_up_miss` sets stale status `operator_follow_up_miss` and `operator_follow_up_miss_at`. Repeat apply skips already matching lifecycle state so idempotent reruns do not churn `updated_at`.
- Operator follow-up misses use the existing `notifications` table and the compatible `leads_waiting` notification type until a dedicated lead-lifecycle type exists. Notifications are persistent, link to the inbox thread when provider thread context exists and otherwise to the pipeline, and dedupe with `dedupe_key = 'lead_lifecycle:operator_follow_up_miss:' || opportunity_id` while the notification is open.
- Phase C remains optional and separate. P5-1 template drafts are deterministic settings-based drafts, not AI provider drafts and not contextual Phase C drafts.
- P5-1 production apply wrote 23 local template follow-up drafts, 41 persistent operator follow-up-miss notifications, and 2 default settings rows, then updated 64 lifecycle-state rows. It wrote zero opportunity business-state mutations. The immediate post-apply dry-run planned zero new drafts, zero new notifications, zero settings inserts, and zero lifecycle-state updates; 5 destructive decisions remained skipped.

P5-3 operator usability remediation:
- Lifecycle notification action URLs must store internal inbox ids, not provider ids. The action service resolves `latestMeaningfulEvent.providerThreadId` against `email_threads.provider_thread_id` plus company and connection context before inserting a notification. If the lifecycle event already carries an internal `email_threads.id`, the service preserves it. If no internal thread exists or the context is synthetic legacy evidence such as `legacy-activity:*`, the notification routes to `/pipeline?opportunityId={opportunity_id}` with label `Open opportunity`.
- The pipeline route accepts `?opportunityId=...` and opens the matching opportunity detail panel after clearing local filters. This is the fallback for any lifecycle notification that cannot safely deep-link into inbox detail.
- Local `opportunity_follow_up_drafts` rows with `origin = 'template_follow_up'` and `status = 'drafted'` are visible in the inbox drafts API and draft chip as source `lifecycle`. They stay local and editable through `/api/inbox/drafts`; editing updates `subject`, `current_body`, `edited_by`, and local timestamps only. Discarding changes the local row to `status = 'discarded'`. This path never creates Gmail/Microsoft provider drafts and never overwrites operator, Phase C, system-handoff, provider-backed, sent, or superseded drafts.
- The inbox draft chip opens lifecycle drafts by resolved internal `email_threads.id` when available and falls back to the linked opportunity context for inline matching. In the thread detail workflow, local lifecycle draft bodies autosave back to the local draft row rather than provider draft APIs. The subject is non-empty by default and is editable through the API/settings surface; no provider draft is created until a separate send flow is explicitly executed by the operator.
- Lifecycle template drafts must have non-empty subjects. The canonical default is the `DEFAULT_FOLLOW_UP_TEMPLATE_SUBJECT` constant (`Following up`), applied instead of an empty string; blank settings values and blank draft-save payloads normalize to that value.
- Persistent lifecycle notifications must remain usable in the rail. The notification fetch ordering surfaces persistent/recent lifecycle notifications first rather than hiding them behind older unread rows under the fetch limit (it prioritizes persistent notifications, then newest `created_at` first). When a notification is read or resolved, `resolved_at` is stamped; the audit row remains in `notifications`. Stale lifecycle notifications are resolved deterministically: meaningful inbound correspondence that clears the opportunity's stale state also resolves the open `lead_lifecycle:operator_follow_up_miss:{opportunity_id}` notification for that opportunity.
- Lifecycle settings source of truth is `public.lead_lifecycle_settings`. `GET/PUT /api/settings/lifecycle` reads and writes that table; it no longer references the nonexistent `companies.lifecycle_settings`. The settings tab is wired to the real fields: follow-up window, second-follow-up archive window, no-correspondence archive window, inbound-unreplied lost window, follow-up subject/body, and archive/lost candidate toggles. Authorization is a granular permission check — not a role filter (`role == 'admin'`/`role == 'owner'`) — and the API writes via upsert on `company_id`.
- P5-3 also performed a one-time production repair of pre-existing P5 rows: 41 `leads_waiting` notification links (broken `/inbox/{providerThreadId}` rewritten to internal-thread or `/pipeline?opportunityId=...` links) and 23 empty draft subjects (backfilled to `DEFAULT_FOLLOW_UP_TEMPLATE_SUBJECT`). This is remediation of historical rows only; the live code above now prevents recurrence.
- The repair was performed via a dry-run/apply repair script, `scripts/lead-lifecycle-p5-3-repair.ts`, with audit artifacts written under `docs/data-cleanup/`. Dry-run/apply targets are separate for notification links/resolution and draft subjects. It writes only the requested markdown artifacts and, in apply mode, only `notifications` link/resolution fields or `opportunity_follow_up_drafts.subject`/`updated_at`; it must not mutate opportunities, clients, activities, email threads, provider state, or email sending.

One-tap operator follow-up (implemented 2026-07-23):
- A due active lead in `quoted`, `follow_up`, or `negotiation` can send its stock template follow-up through `POST /api/leads/[opportunityId]/follow-up`. The browser supplies only an idempotency key; the server owns the mailbox, recipient, signature, provider subject/thread, source event, and rendered copy.
- The current stock body is `Hi {{first_name}}, just checking in to see if you had any questions about the quote. No pressure — I wanted to make sure you had everything you needed.` Existing company-customized templates remain authoritative; the migration updates only rows still carrying the former stock body.
- A send is allowed only when every conversation linked to the opportunity resolves to the same mailbox and every provider thread is freshly inspected. A customer response or equal/newer message on any linked thread blocks the action. The final database claim repeats an opportunity-wide equal/newer meaningful-event fence under the lead lock.
- Provider acceptance atomically marks the template draft sent, advances unanswered-follow-up state only while this send remains the newest durable correspondence truth, resolves the operator-miss nudge when appropriate, schedules the effective comeback, and creates one `lead_follow_up_sent` rail receipt. If equal/newer correspondence already exists, delivery is still receipted but the newer lifecycle truth wins and the comeback remains null.
- Deterministic idempotency and the durable send-intent receipt prevent duplicate provider sends. Settled rejections and pre-provider claim failures explicitly report definitive no-delivery; accepted-but-unreconciled sends remain recovery-pending.

#### Update — 2026-05-29: P1 Data-Correctness Remediation + P3 Automation Cron

This entry records the 2026-05-29 work that landed alongside the P4/P5 production closeouts above: the P1 historical data-correctness remediation (applied to production), a critical correction to the email-matching model, and the P3 automation cron (built and committed locally, not yet deployed).

##### P1 data-correctness remediation (APPLIED to production 2026-05-29)

The P1 dry-run artifacts (see `docs/data-cleanup/`) identified three classes of historical data damage. They were remediated via paired dry-run→apply scripts under `docs/data-cleanup/`. All de-aggregation was done by re-stamping synthetic thread ids, never by splitting or deleting correspondence rows.

- **DW1 — blank-thread bucket de-aggregation.** A single empty-string `provider_thread_id` thread (`dd15de37`, ~2010 messages) had become a junk aggregation bucket: every email with a blank provider thread id had collapsed into it, plus the blank join row and ~2198 blank activities. Remediation stamped each affected row with a per-opportunity synthetic `legacy:<id>` thread id so the correspondence is re-partitioned back to its true opportunity rather than co-mingled in one bucket. No correspondence rows were split or deleted. The junk aggregate shell opportunity `a760f45f` ("New Lead", blank client) was discarded and tagged `legacy-aggregate`. The one real customer opportunity caught in the bucket, `aeb65f87` (Marcia Farquhar, `negotiation`), was preserved intact and only de-linked from the junk bucket.
- **DW3 — identity/title contamination.** 19 opportunity titles had been contaminated with the operator's own name ("Jackson Sweet"). Their titles were re-derived from the correct source facts.
- **DW2 — link reconciliation.** 2 safe re-points were applied (a Jonathan Anderson archived-duplicate opportunity's thread link was re-pointed to its live twin). 48 split threads + 19 flagged rows could NOT be auto-fixed: they cross terminal boundaries or require operator judgment to resolve correctly. These are an **OPERATOR REVIEW QUEUE**, not an auto-remediable set, and must not be machine-fixed.
- **Business-state guard held throughout.** Aggregate row counts were unchanged across the entire remediation — opportunities 390, clients 380, activities 3106, email_threads 3564 — confirming nothing was split, duplicated, or deleted. The only intended business change was the single `a760f45f` junk-shell discard.

##### Critical matching insight — `activities.from_email` is the company's own outbound address

`activities.from_email` stores the COMPANY'S OWN outbound sending address (e.g. `canprojack@gmail.com`), NOT the inbound customer address. Therefore **`from_email → customer/client` is an INVALID matching signal** and must never be used to identify or enrich the customer side of an opportunity. Matching and enrichment must rely on the canonical thread/join structure (`email_threads`, `opportunity_email_threads`) and provider message id (`activities.email_message_id`), together with parsed contact-form submitter identity — not on `from_email`. This reshapes P2 enrichment design: any P2 path that inferred a customer email/name from `from_email` is wrong and must use canonical thread structure + parsed submitter identity instead.

##### P3 automation cron (BUILT, committed locally, NOT yet deployed)

A daily automation cron was built for the lead lifecycle: `GET /api/cron/lead-lifecycle`, `CRON_SECRET`-gated, scheduled daily at 13:00 UTC. It is committed locally but NOT yet deployed — and by design it cannot fire in production until deployed.

- **Non-destructive auto-execution only.** The cron auto-executes only the NON-destructive P4/P5 actions: creating local `template_follow_up` follow-up drafts and emitting operator-miss notifications. It is idempotent via the open-template unique index (one open `template_follow_up` draft per opportunity) and notification `dedupe_key`.
- **Destructive actions are dry-run candidates only.** The 4 destructive actions (`archive_after_two_unanswered_followups`, `archive_no_meaningful_correspondence`, `move_to_lost_operator_no_response`, `reactivate_on_related_inbound`) are emitted as DRY-RUN candidates only. The cron never calls the guarded RPC `public.execute_opportunity_lifecycle_guarded_action(...)`; destructive execution remains operator-approved through the P4-12 dry-run→approval→guarded-RPC path.
- **Fragmented correspondence is skipped for destructive emission.** Opportunities whose correspondence is fragmented or quarantined — identifiable by `legacy%` synthetic thread ids (including the DW1 `legacy:<id>` stamps and `legacy-activity:*` boundaries) — are skipped for destructive candidate emission, because their correspondence truth is not clean enough to drive an archive/lost decision.
- **Deploy/push deliberately held.** The cron cannot run in production until it is deployed. Deploy and push are deliberately held until the entire lead-lifecycle initiative completes, consistent with the initiative-wide hold-push policy.

#### Update — 2026-05-29: P5 Merge/Disposition/End-States, P6 Project Conversion, Operator Review Queue, Ingestion Backstop

This entry records the remaining lead-lifecycle build that landed after the P4/P5-1/P5-3 production closeouts above. Everything in this block is **committed locally on the web branch `feat/lead-lifecycle-p5-1` and NOT yet deployed or applied to production.** Six additive migrations are written but unapplied; the coordinated release runbook lives at `docs/data-cleanup/lead-lifecycle-release-runbook-2026-05-29.md`. The Phase-C learning gate `LIFECYCLE_LEARNING_ENABLED` stays off until go-live. This work implements the merge/disposition/conversion intent already described above under "Lifecycle States, Visibility, and Outcomes" (`merged`, `converted_to_project`) — it does not redefine that intent.

This update supersedes the earlier "schema gaps" notes for merge candidates and dispositions: P5 introduces the `opportunity_merges` audit table, the `opportunity_dispositions` history table, and `duplicate_reviews.migration_manifest` that those gaps anticipated.

##### P5 — guarded transactional merge, dispositions, and end-states (backend)

Merge is implemented as two guarded `SECURITY DEFINER` RPCs, mirroring the P4-12 guarded-action boundary. Both run as a single database transaction, take `FOR UPDATE` row locks on both the winner and the loser, and roll the entire merge back on any error so a partial re-point can never be left behind.

- **`public.execute_opportunity_merge_guarded(...)`** — absorbs a loser opportunity into a winner. It performs a complete FK re-point of all 14 opportunity child relations (correspondence events, lifecycle state, follow-up drafts, email-thread links, activities, comments, site visits, photos, estimates, line-item scope, lifecycle action audit, dispositions, prior merges, and notifications) onto the winner. The loser is soft-deleted (not hard-deleted), given a `merged_into_opportunity_id` pointer, and stamped with a jsonb `migration_manifest` recording exactly what moved. Lifecycle-state counters are merged conservatively (the more-cautious value wins — e.g. it never resets an unanswered-follow-up count downward), and the consolidated thread set is re-pointed so all correspondence reads against the surviving opportunity.
- **`public.execute_client_merge_guarded(...)`** — absorbs a loser client into a winner across all 17 client references. Each reference is re-pointed on **both** the FK-backed `*_ref` column **and** the legacy text `*_id` mirror so iOS clients still reading the legacy mirror stay consistent. Portal handling is explicit: the loser's portal messages are re-pointed to the winner, and the loser's portal tokens/sessions are revoked so a stale magic link cannot resolve to the merged-away client.
- Both RPCs are **service-role/server-only** trusted boundaries; ordinary authenticated users do not receive `EXECUTE` and must not call them through PostgREST. RLS/company checks remain defense-in-depth, not the approval gate.
- **§2.4 dedupe** runs inside the transaction: when re-pointing would create a duplicate child (e.g. the same `(thread_id, connection_id)` link or the same provider message id on both sides), the duplicate is collapsed rather than inserted, so the merge cannot violate the existing partial-unique constraints.
- **Idempotency** is enforced by a `merge_key` (deterministic winner/loser/key tuple recorded in `opportunity_merges`); a repeated apply with the same key is a no-op and does not double-re-point or double-soft-delete.
- **Snapshot guard.** Like the P4-12 RPC, the merge computes its before-state from the locked live rows. A client-supplied expected snapshot is optimistic verification only; on disagreement the RPC records a guarded skip (`snapshot_mismatch`) and does not report the merge as applied.

New additive tables and columns (all iOS-safe — new nullable columns and new tables only):

- **`opportunity_merges`** — one row per merge: company, winner, loser, `merge_key`, jsonb manifest of moved children, actor, and timestamps. Append-only audit.
- **`opportunity_dispositions`** — append-history of business outcomes for an opportunity. `disposition` is one of `won`, `lost`, `disqualified`, `discarded`, `merged`, `converted_to_project` (the exact vocabulary from the "Lifecycle States" table above). `reason_code` is permissive free text (not a CHECK enum) so operators are never blocked from recording a real-world reason the schema didn't anticipate. A partial-unique index enforces at most one **active** disposition row per opportunity while keeping the full history.
- **`duplicate_reviews.migration_manifest`** — jsonb column recording what a reviewed merge moved, so the operator review queue can show the exact effect of a resolution.
- **`merged_into_opportunity_id` / `merged_into_client_id`** — soft-delete pointers on opportunities and clients identifying the surviving record after a merge.

Field-survivorship decision — **SURFACE EVERY CONFLICT.** Merge never silently overwrites a non-blank value. For each canonical field, a blank on the winner is auto-filled from the loser (fill-blank, no operator action). Every field where both sides hold a non-blank but *different* value is surfaced to the operator as a conflict the operator must resolve explicitly; nothing is auto-picked by recency, confidence, or side. The operator's resolution is submitted as `confirmedOverrides` (see frontend below) and applied inside the guarded RPC transaction.

##### P6 — automatic project conversion on Won

Conversion fires automatically when an opportunity moves to `won`, via a guarded transactional RPC that creates the linked project and wires the relationship both ways.

- The RPC creates the `projects` row and writes the FK-backed `opportunity_ref` on the project plus the FK-backed `project_ref` on the opportunity, and writes the legacy text mirrors alongside each FK so iOS stays consistent.
- It **re-links estimates** from the opportunity onto the new project, writing both the FK-backed `project_ref` and the legacy `project_id` text mirror on each estimate.
- It writes an `opportunity_dispositions` row with `disposition = 'converted_to_project'`.
- It is **idempotent and repairing**: an opportunity that already has a `project_ref` is never converted twice, but a repeat call repairs all four project/opportunity mirrors and still honors a later `p_win_opportunity = true` request. The opportunity remains `won`, remains linked to its project, and is **not archived** — conversion is not a removal from the pipeline, it is a hand-off that preserves the sales trail (matching the "Project inherits sales trail" intent above).
- Direct project writes mirror `projects.opportunity_ref` and legacy `projects.opportunity_id`. A database invariant repairs the reverse `opportunities.project_ref` / `project_id` mirrors and writes one `won` transition for a newly linked project. Approval-queue RFQ creation may explicitly defer the win inside the conversion transaction; moving that linked project to `accepted`, `in_progress`, `completed`, or `closed` then wins the opportunity. Unrelated project edits do not alter sales stage.
- The invariant rollout locks the project and opportunity tables for a guarded one-time reconciliation. It aborts on ambiguous or cross-company history, releases active leads from soft-deleted projects, and normalizes only provable reciprocal mirrors. That repair never changes sales stage, manual-stage ownership, lead assignment, close fields, or project/task membership.
- Additive iOS-safe `projects` columns support the link and analytics: `opportunity_ref` (FK to opportunities), `estimated_value`, `source`, and `platform_metadata` (jsonb).

##### Frontend — merge conflict resolution + operator Lead Data Review Queue

- **Merge conflict-resolution UI.** The `DuplicateReviewSheet` gains a **RESOLVE** step. For a candidate merge it shows each surveyed canonical field with the winner value, the loser value, and the auto fill-blank result. Where both sides conflict, the operator picks the surviving value per field; the sheet submits the operator's choices as `confirmedOverrides`, which the backend applies inside `execute_opportunity_merge_guarded` / `execute_client_merge_guarded`. Fields that were auto fill-blank require no operator action and are shown as already-resolved.
- **Lead Data Review Queue — `/admin/data-setup`.** This is the operator surface for the DW2/DW3 review set that the P1 remediation flagged as not auto-fixable (it must not be machine-fixed; see the P1 remediation entry above). It presents the ~48 split-thread candidates and ~18 terminal/live link candidates as actionable review rows, each resolving to a merge, a re-point, or a disposition through the guarded RPCs. The ~2198 de-aggregated blank-bucket activities from DW1 are **not** actionable rows — they are surfaced only as a muted count so the operator understands the scale of what the `legacy:<id>` re-stamping already partitioned, without being asked to hand-touch each one.
- **Data Review authorization and mailbox identity.** Provider thread ids are mailbox-scoped, never globally unique. Queue reads derive actor/company from the authenticated OPS user, group by exact `(connection_id, provider_thread_id)`, and return an item only when every linked lead passes canonical pipeline-view + inbox-view authorization. Re-point and quarantine actions run as one actor-aware, service-only transaction after canonical pipeline-edit + inbox-view authorization, company serialization, and exact mailbox/thread row locks; the actorless legacy mutation transport is revoked. Activities with an unknown legacy connection are not claimed or changed by review actions. Terminal quarantine is recorded durably and idempotently. Success notifications use the trusted identity-returning notification seam with a connection-scoped dedupe key, and notification reconciliation failure never makes a completed data correction appear retriable.
- **New notification types.** Two dedicated lead-lifecycle notification types are added to the rail: `duplicates_merged` (emitted when a merge completes) and `data_review_resolved` (emitted when an operator clears a review-queue item). These replace the earlier P4-8/P5-1 stopgap of borrowing the `leads_waiting` type for lifecycle events; the action URLs follow the P5-3 rule of storing internal inbox/pipeline ids, never provider ids.

##### Ingestion backstop (CW1)

The ingestion path is hardened so the blank-provider damage the P1 remediation cleaned up cannot recur, while staying iOS-safe (ingestion never rejects a write that an older iOS client depends on):

- **CW1 blank-provider rewrite trigger.** A database trigger rewrites a blank (`''`) `provider_thread_id` to a synthetic `legacy:<id>` value on write rather than rejecting the row. This is the same partitioning scheme the DW1 remediation applied retroactively, now enforced at ingestion so new blank-provider rows never collapse into a shared junk bucket. It **never rejects** — rejection would break older iOS clients — it only rewrites.
- **Dedupe-by-message-id fix.** Ingestion dedupes on provider message id so a re-synced message does not create a second activity/correspondence event.
- **Legacy email-webhook retired.** The legacy email-webhook endpoint now returns HTTP 410 Gone; provider sync is the single supported ingestion path.

##### State of play

- **6 additive migrations are written but UNAPPLIED**: `opportunity_merges`, `opportunity_dispositions`, `duplicate_reviews.migration_manifest`, the `merged_into_*` pointers, the `projects` conversion columns (`opportunity_ref`/`estimated_value`/`source`/`platform_metadata`), and the CW1 ingestion trigger. All are additive and iOS-safe (new nullable columns / new tables only), consistent with the iOS↔Supabase additive-only constraint.
- **Coordinated release runbook**: `docs/data-cleanup/lead-lifecycle-release-runbook-2026-05-29.md` sequences migration apply, edge/cron deploy, and the operator review-queue rollout.
- **`LIFECYCLE_LEARNING_ENABLED` stays gated** (Phase C off) until go-live. Merge, disposition, conversion, the review queue, and the CW1 backstop are all deterministic and do not require Phase C.
- **Everything is held local.** Per the no-push-until-complete directive, the web branch `feat/lead-lifecycle-p5-1` and this bible branch are committed locally only; nothing is pushed, deployed, or applied until the entire initiative is complete.

#### Phase C Off vs Phase C On

| Capability | Phase C Off | Phase C On |
|---|---|---|
| Email ingestion, provider thread/message proof, activity logging | Required | Required |
| Conservative client/opportunity matching | Required | Improved by AI context |
| Opportunity field enrichment | Deterministic only when safe | Better freeform extraction and confidence |
| Stage movement | Deterministic, conservative | Context-aware suggestions or high-confidence actions |
| Stale detection | Opportunity-level, deterministic | Better understanding of related contacts and context |
| Follow-up drafting | Template-based from settings | Can also create smarter contextual drafts |
| New-thread relationship matching | Exact contact/phone/address/project-state gates | Better household/project graph suggestions, still non-destructive |
| Merge decisions | Manual operator action | AI may suggest, never destructive by itself |
| Project conversion | Manual, or high-confidence deterministic rule only | Better won-confidence detection and handoff drafting |

Phase C should never be the hidden storage location for canonical lead data. If Phase C extracts a durable fact, that fact belongs on the appropriate client/opportunity/activity/thread record with provenance.

#### Lifecycle States, Visibility, and Outcomes

Visibility is separate from business outcome:

| Concept | Meaning | Reporting impact |
|---|---|---|
| `active` | Visible in active pipeline | Counts as live pipeline |
| `archived` | Hidden from active pipeline, reversible | Does not count as won/lost |
| `won` | Valid opportunity became work | Counts as conversion |
| `lost` | Valid, qualified opportunity did not close | Counts against close rate |
| `disqualified` | Real inquiry, but not a fit | Counts toward lead-quality/ad-targeting analysis, not close-rate loss |
| `discarded` | Should not have been a lead: spam, vendor, applicant, internal, platform noise, test data | Counts toward system/data-quality analysis, not sales performance |
| `merged` | Duplicate/fork created in error and absorbed into another opportunity | Losing record is removed from normal views after its data is integrated |
| `converted_to_project` | Won opportunity has an operational project link | Project inherits sales trail |

Archive means "remove from active pipeline." It does not delete the opportunity, email threads, activities, or source proof. A matched inbound from any known or newly matched related contact should unarchive/reactivate the opportunity.

Merge is different from archive. Merge means one opportunity was created in error as a fork. The merge operation must move useful data, activities, email threads, contacts/sub-contacts, field provenance, estimate/project links, and source message IDs into the winning opportunity, then remove the losing opportunity from normal data views. If hard delete is unsafe for audit or FK constraints, product behavior should still be "deleted after merge," not "archived as a normal stale/lost lead."

#### Stale Lead and Follow-Up Intent

Staleness belongs to the opportunity, not an individual email thread.

Rules:
- Won, lost, converted-to-project, and already archived opportunities are not monitored for stale-lead automation.
- Meaningful correspondence excludes provider noise, automated bounces, marketing, internal-only chatter, duplicate sync rows, and system notifications. In normal client threads, actual client emails should generally count.
- If OPS sent the last meaningful message and the configured threshold passes, mark the opportunity as needing follow-up and create a template follow-up draft.
- Follow-up drafts are lifecycle automation, not Phase C. They are generated from configurable settings templates. The standard default is: `Hi {{first_name}}, just checking in to see if you had any questions about the quote. No pressure — I wanted to make sure you had everything you needed.`
- After two OPS follow-ups with no meaningful customer response, archive the opportunity 7 calendar days after the second follow-up.
- If there has been no meaningful correspondence for 14 calendar days, archive the opportunity unless it has a terminal or protected state.
- If the last meaningful email was inbound and unreplied, do not treat it as a cold customer. If it is under 30 calendar days old, surface it as an operator follow-up miss or archive only as a visibility action. If it is over 30 calendar days old and the lead had moved beyond qualified, move it to `lost` with a reason such as `operator_no_response`.
- If a matched inbound arrives from any linked or high-confidence related contact, reset stale timers, unarchive if needed, enrich the opportunity, and re-evaluate stage.

Settings should eventually expose follow-up cadence, follow-up templates, stale thresholds, and any manual keep-active or automation-pause control. If a keep-active/automation-pause control does not exist yet, it is a product gap, not a reason to invent hidden behavior.

#### Deliberate, Cycle-Aware Lead Follow-Up (iOS + OPS-Web, 2026-07-23; hardened 2026-07-29)

The iOS chase strip gives an eligible **Due Today** or **Overdue** lead a bounded `HOLD TO REVIEW` control. The first hold opens a provider-fresh review sheet with recipient, sender, subject/body, and `Settings → Comms → Lifecycle`; delivery still requires an explicit `SEND FOLLOW-UP`. `Skip review next time` is scoped to the company + operator, after which the strip says `HOLD TO SEND`. VoiceOver uses its standard explicit double-tap action. The hold recognizes simultaneously with the card's horizontal stage gesture and cancels on movement, so a nested control never steals or ambiguously competes with stage advance/regress.

This remains a provider send, not a composer shortcut and not an optimistic "handled" mutation. `YOUR MOVE` continues to show `HANDLED`; the normal `EMAIL` contact action continues to open the editable email composer. If server-side mailbox/thread checks show that the shortcut is unsafe or unavailable, the chase strip falls back to the ordinary handled/email paths.

iOS first uses authenticated GET on the same route for the read-only preview; no draft, intent, provider mutation, or lifecycle write occurs. The preview resolves any deliberate edit on the exact still-bound stock draft and includes the effective mailbox signature, so its body is the actual rendered message. GET also returns an opaque SHA-256 `previewFingerprint` over the exact server-derived mailbox/thread/reply source/recipient/sender/subject/rendered body. An explicit review send returns that fingerprint alongside the durable UUID `idempotencyKey`; POST recomputes it after the fresh preflight, then checks the final bound draft again, and refuses before provider delivery when reviewed facts changed. A skip-review hold omits the fingerprint but keeps every authorization, provider, and cycle gate. Storage is scoped by company + actor + opportunity + canonical chase cycle. The same key survives network/auth/permission changes, unavailable state, provider-accepted/pending reconciliation, delivery-unknown state, and app restart; a later cycle gets a new key only after canonical handled/outbound progress advances. It is cleared only after a fully reconciled receipt or definitive provider rejection/invalid request. While preview/send is unresolved, the strip shows `REVIEWING…`, `SENDING…`, `SYNCING…`, or `CHECK EMAIL` and blocks another attempt for that lead.

The OPS-Web route derives every irreversible transport fact from canonical server state:

- canonical actor and company from the bearer token;
- the active, unconverted, quote-bearing (`quoted`, `follow_up`, or `negotiation`) opportunity, its company-local due day, and its contact email;
- one unambiguous existing `opportunity_email_threads` / `email_threads` provider thread and its pinned connection;
- the live provider thread, whose newest message must be an OPS outbound from that connection or configured sender alias;
- the contact as an existing thread participant;
- the company follow-up template (or the standard default), rendered placeholders, and effective mailbox signature;
- the bound `template_follow_up` draft and source correspondence event used by the durable send intent.

Eligibility is cycle-aware on both iOS and the server. `next_follow_up_at` must be due, must not predate `stage_entered_at`, and both canonical `last_outbound_at` and the provider source outbound must predate the due boundary. A manual outbound at or after the boundary therefore satisfies that cycle and removes the action before a duplicate stock follow-up can be offered or executed.

The shortcut never accepts a client-supplied mailbox, provider thread, recipient, subject, body, or signature, and it never starts a new provider thread. GET and POST both read the live provider conversation; POST reads it again inside the mailbox lease immediately before delivery. A newer customer inbound, changed newest outbound, cycle-satisfied outbound, ambiguous thread, changed lead, missing mailbox/signature/recipient, or authorization mismatch fails closed. An opportunity-wide database fence prevents a different thread from opening a second unresolved template-follow-up send, and the bound draft content is frozen across the provider boundary. Migration `20260729230000_pipeline_follow_up_reliability.sql` adds the final database trigger check immediately before prepared→sending.

Lead state advances only after the provider has accepted the message and the send has reconciled canonically. Migration `20260723233000_operator_one_tap_lead_follow_up.sql` owns that atomic transition through service-role RPC `reconcile_operator_template_follow_up_send_as_system(intent_id)`: it marks the bound draft sent, increments the unanswered-follow-up count exactly once when no later meaningful event won, stamps the second-follow-up time at count 2+, clears the due/operator-miss stale state, resolves the prior operator-miss notification, updates a still-current lead to handled, and writes an intent-scoped `lead_follow_up_sent` notification. The effective comeback is provider acceptance +3 days unless the operator had already chosen a sooner future check-in on a later company-local day. If newer meaningful activity or terminal state won while reconciliation was running, delivery is still receipted but OPS preserves that newer truth and stores no comeback for this send.

Provider-originated manual outbound mail uses the same chase-state truth through service-only RPC `reconcile_manual_outbound_follow_up_cycle_as_system(company_id, opportunity_id, correspondence_event_id)`. The RPC accepts only one canonical, meaningful, projected OPS outbound event bound to its exact activity, mailbox, provider thread, and opportunity. `opportunity_manual_outbound_cycle_receipts` makes replay idempotent before any counter or due-date change. Its insert targets the verified unique constraint `opportunity_manual_outbound_cycle_r_correspondence_event_id_key` explicitly; a bare `ON CONFLICT (correspondence_event_id)` is forbidden because the RPC returns an identically named output field and PL/pgSQL resolves that target ambiguously at runtime. Migration `20260730220000_fix_manual_outbound_follow_up_conflict_target.sql` replaces only that target and preserves the service-role gate, company fence, row locks, event/activity bindings, lifecycle precedence, receipt contract, and grants.

The same function also returns an output field named `opportunity_id`. Its
later lifecycle-state upsert therefore must use `ON CONFLICT ON CONSTRAINT
opportunity_lifecycle_state_pkey`, never `ON CONFLICT (opportunity_id)`.
Production hotfix `20260731183127_fix_manual_outbound_follow_up_lifecycle_conflict_target`
made that exact replacement on 2026-07-31 and preserved service-role-only
execute; the matching repository migration records deployment parity.

A fully reconciled response supplies the immutable outcome receipt plus the canonical server opportunity when available. iOS applies a supplied canonical row, or refreshes after a receipt-only replay. When the send still owns chase state it removes the lead from Due/Overdue and surfaces `FOLLOW-UP SENT · BACK <date>`; when newer truth won it confirms only `FOLLOW-UP SENT`. On an HTTP 202 accepted/pending or delivery-unknown result, iOS does not update `handled_at`, synthesize a comeback, or move the lead locally; a later canonical refresh may resolve the pending UI only when it proves an outbound message, handled state, and a future follow-up date. No undo is offered for sent email.

Separately, a deterministically linked manual provider outbound now reconciles the current chase cycle through service-only `reconcile_manual_outbound_follow_up_cycle_as_system(company_id, opportunity_id, event_id)`. Only the newest meaningful, projected, non-noise OPS outbound from exact `sync_activity` correspondence can run. One immutable event receipt makes it idempotent; the transaction stamps handled/timeline truth, satisfies the old cycle only when the outbound occurred at or after its due boundary, advances the next check-in by `lead_lifecycle_settings.follow_up_after_days` (default 7) while preserving an explicitly sooner future check-in, recalculates stale/unanswered state, supersedes only an open stock template draft, and resolves its operator-miss notification. Internal, ambiguous, orphaned, duplicate, or unprojected mail cannot mutate a lead. The Phase-C opportunity summary refreshes after the canonical meaningful event when that feature is enabled.

Primary implementation sources:

- `ops-web/src/app/api/leads/[opportunityId]/follow-up/route.ts`
- `ops-web/src/lib/api/services/lead-follow-up-send-service.ts`
- `ops-web/src/lib/api/services/email-send-reconciliation-service.ts`
- `ops-web/src/lib/api/services/manual-outbound-follow-up-cycle-service.ts`
- `ops-web/supabase/migrations/20260729230000_pipeline_follow_up_reliability.sql`
- `ops-web/supabase/migrations/20260723233000_operator_one_tap_lead_follow_up.sql`
- `ops-ios/OPS/Services/LeadFollowUpService.swift`
- `ops-ios/OPS/ViewModels/PipelineViewModel.swift`
- `ops-ios/OPS/Views/Leads/Components/LeadChaseStrip.swift`
- `ops-ios/OPS/Views/Leads/Sheets/LeadFollowUpReviewSheet.swift`
- iOS hosts: `LeadsTabView.swift`, `PipelineStageListView.swift`, `LeadDetailView.swift`, and `Triage/LeadTriageCard.swift`

#### Drafting and Learning Intent

Drafts can come from multiple origins:

| Origin | Purpose |
|---|---|
| `operator` | Human-created draft |
| `template_follow_up` | Settings-driven stale-lead follow-up |
| `phase_c` | AI/contextual draft |
| `system_handoff` | Future project or lifecycle handoff draft |

Multiple draft origins may coexist for the same opportunity/thread. A manual draft does not block Phase C from creating a Phase C draft, and a template follow-up does not overwrite a manual draft. The operator chooses which draft to edit/send.

Every generated draft must retain:
- original generated body and subject
- final sent body and subject
- origin (`operator`, `template_follow_up`, `phase_c`, etc.)
- linked opportunity id, provider thread id, and source message id where applicable
- generated_at, edited_at, sent_at, discarded_at
- user/editor id
- edit diff or equivalent edit-distance representation
- final disposition: sent, discarded, replaced, expired

Phase C learns from the delta between generated drafts and the sent version. It should learn from sent emails, not abandoned drafts. Template follow-up edits are also learning signal because they show how the operator personalizes lifecycle communication.

#### New Thread, Same Customer, Different Job

Matching must account for repeat customers and households. The same client or
same property-qualified address does not automatically mean the same
opportunity. Locality-only values such as `Victoria`, `Langford`, `Esquimalt`,
`Tillicum`, `Henderson`, `North Saanich`, or `Saanich Cedar Hill area` are
regional context only and must never establish identity, deduplication, merge,
or opportunity/project linkage.

When a new thread or new contact appears, matching should consider:
- exact known client/sub-contact/participant email
- phone number
- shared property-qualified address; locality remains non-identity context
- spouse/partner/project-manager relationship
- quoted prior thread content
- subject/body scope similarity
- timing/recency
- existing opportunity and project state

Guidance:
- If an existing opportunity at the same property-qualified address is active, RFQ, estimating, quoted, follow-up, or negotiation, the new thread is likely the same job.
- If an existing project at the same property-qualified address is active/in progress, the new thread is likely project communication or same-job context.
- If the prior project is completed/closed and the scope is distinct, create a new opportunity.
- If confidence is not high, create a separate lead and provide a merge path rather than over-linking.

#### Automation Boundary

| Action | By deterministic algorithm | Phase C-assisted | Do not automate blindly |
|---|---|---|---|
| Deduplicate exact provider message IDs | Yes | Not needed | - |
| Link a message on an already-linked provider thread | Yes | Not needed | - |
| Update correspondence counts from linked activities | Yes | Not needed | - |
| Fill blank fields from explicit contact-form values | Yes | Can improve extraction | Do not overwrite operator truth |
| Generate follow-up drafts from templates | Yes | Can create an alternate smarter draft | Do not auto-send unless separately enabled |
| Reset stale timer on matched inbound | Yes | Can improve matching | Do not reset from provider noise |
| Link a new thread to an opportunity | Only with strict high-confidence gates | Yes, improves confidence | Do not link from weak evidence |
| Determine same customer/new job vs same job | Conservative only | Yes, materially useful | Do not collapse repeat jobs into one opportunity |
| Move to lost for operator no-response after 30+ days beyond qualified | Yes, if state is clear | Can improve classification | Do not mark unqualified noise as lost |
| Archive stale opportunities | Yes, if opportunity-level stale rules pass | Can improve confidence | Do not archive terminal/protected opportunities |
| Merge opportunities | No | Suggest only | Destructive, requires operator confirmation |
| Delete losing fork after merge | No | Not needed | Only after confirmed merge and data migration |
| Auto-convert to project | Only on explicit high-confidence acceptance and configured conversion path | Can improve won confidence | Do not convert vague language |
| Treat platform sender as customer | No | No | Store as source metadata only |

#### Project Conversion Intent

When an opportunity converts to a project, the project must inherit as much sales context as possible. The conversion contract should be maintained against the live `opportunities` and `projects` schemas and should carry over at least:
- client and sub-contact graph
- address/location
- scope/description
- estimated value and quote/estimate context
- source/platform metadata
- linked email threads
- activities and source message IDs
- attachments/photos and estimate files where applicable
- stage/history and field provenance

Project conversion must not sever the sales trail. The project should link back to the opportunity, and the opportunity should link forward to the project.

#### Update — 2026-06-04: Archive-first auto-cleanup (destructive auto-execution live; supersedes "dry-run candidates only")

This entry supersedes two earlier claims for the `/api/cron/lead-lifecycle` daily cron: that destructive actions are "dry-run candidates only" and that the cron "never calls the guarded RPC" (P3 automation cron note, 2026-05-29), and that operator no-response leads are moved to **lost** for beyond-qualified stages (P4 evaluator + P4-12). The cron now **auto-executes** destructive dispositions for opted-in companies, and the auto cleanup only ever **archives**.

Source: web `feat/lead-lifecycle-auto-disposition` → ops-web `main` (PR #84, squash `9ca031af`). Migration `supabase/migrations/20260604221634_archive_operator_no_response_guarded_action.sql`, applied to prod `ijeekuhbatykdomumfjx` 2026-06-04.

- **Destructive auto-execution, per-company opt-in.** When a company has opted in, the cron calls `public.execute_opportunity_lifecycle_guarded_action(...)` (apply mode) for destructive decisions instead of only surfacing a review notification. Gating lives in the cron (`destructiveActionAutoEnabled`): all three archive actions **and** `reactivate_on_related_inbound` are gated on `auto_archive_enabled`; `move_to_lost_operator_no_response` would be gated on `auto_lost_enabled`. The cron mints a deterministic per-day approval key `<opportunityId>:<action>:<YYYY-MM-DD>` so the apply-mode `missing_approval` guard passes and a same-day re-run hits the `duplicate_applied_action` guard instead of re-applying. Companies **not** opted in keep the prior dry-run review-notification path. All server-side structural guards (terminal/protected stage, deleted, converted/linked, already-archived, lost-stage allow-list, related-inbound, snapshot mismatch) remain enforced.
- **Archive-first policy — new `archive_operator_no_response` action.** The evaluator now emits `archive_operator_no_response` for **any active stage** (`new_lead`, `qualifying`, `quoting`, `quoted`, `follow_up`, `negotiation`) whose latest meaningful inbound went unanswered past `inbound_unreplied_lost_days`, gated on `auto_archive_enabled`. This replaces the old beyond-qualified `move_to_lost_operator_no_response` auto-production **and** catches early-stage "forgot to follow up" leads that previously only ever produced an `operator_follow_up_miss` nudge forever (e.g. a `new_lead` with a stale unanswered inbound). The disposition is **archive** (sets `archived_at` only; no stage change, no `opportunity_dispositions` row), which is reversible and judgment-free. An unanswered inbound **under** the window still yields `operator_follow_up_miss` (the nudge); the cascade is nudge-then-archive.
- **Lost/discard classification deferred to phase C.** The auto cleanup deliberately never declares a lead **lost** or **discarded** — those carry win/loss-reporting meaning. `move_to_lost_operator_no_response` is no longer produced by the evaluator, but its full executor + audit + `opportunity_dispositions` write path (RPC + action-service) is left **intact** for phase C to drive once intelligent lost-vs-archive-vs-discard determination ships. The archive decision's evidence carries a `beyondQualified` boolean — the signal phase C uses to reclassify (a beyond-qualified archive is a strong lost candidate; an early-stage one is more likely cold/forgotten).
- **Guarded RPC + audit CHECK extended.** `archive_operator_no_response` archives identically to `archive_no_meaningful_correspondence` (allowed mutation field `archived_at`; same archive payload guard and `archived_at IS NULL` update). It was added to the RPC's action allow-list + the four archive-group branches, and to the `opportunity_lifecycle_action_audit_action_check` CHECK. The function body was patched in-place via `pg_get_functiondef` string surgery with a five-insertion assertion (no hand-retype of the 200-line SECURITY DEFINER body). Verified by a rolled-back sentinel that archived a `new_lead` end-to-end through the live RPC in the cron's service-role context, leaving no trace.
- **First-run blast radius (the two opted-in companies, Canpro + Maverick, 2026-06-04).** Surgical: 1 `archive_operator_no_response` at Canpro (a quoted lead, 37 days unanswered) and 1 `archive_no_meaningful_correspondence` at Maverick (zero correspondence, stale) — 2 leads across 38 active opportunities. Both reversible.
- **Deploy state.** Merged to ops-web `main`; the migration is live on prod. ops-web Vercel **auto-deploy is OFF**, so the new cron behavior does **not** run until the next **manual** ops-web production deploy. Until then the deployed cron retains the prior dry-run-only behavior.

### Provider Support

**Prepared hardening status (2026-07-13):** The provider identity, cursor, OAuth, and correspondence rules in this section are implemented in the isolated `ops-web-email-pipeline-hardening` worktree but are **not deployed**. Five executable expand migrations are prepared but unapplied. Contract SQL `2050` is held under `docs/migrations/`, outside the normal migration runner, so apply-all cannot contract the schema before the compatible application is proven. The rollout is `2000`-`2040` expand -> application deploy and controlled sync proof -> separate reviewed `2050` contract. Production Canpro was inspected read-only and currently has one Gmail connection and no Microsoft 365 connection.

| Provider | Auth | Scopes | Incremental Sync | Push Notifications |
|----------|------|--------|-------------------|--------------------|
| Gmail | Google OAuth 2.0 | `https://mail.google.com/` | History API (`startHistoryId`) | Google Cloud Pub/Sub (`users.watch()`) |
| Microsoft 365 | Microsoft Identity Platform | `User.Read`, `Mail.Read`, `Mail.ReadWrite`, `Mail.Send`, `offline_access` | Mail-folder inventory delta plus one resumable message delta per live folder | Graph Change Notifications (`POST /subscriptions`) |

A single company can connect both providers (e.g., owner uses Gmail, office manager uses M365). Each connection is a separate `email_connections` row with its own sync profile, webhook subscription, and sync token. The target connection identity is normalized email unique by `(company_id, provider, email)`, so the same address may exist once per provider without sharing tokens, cursors, webhook state, or settings. Expand migration `2030` adds that identity alongside the live provider-agnostic index and normalizes old/new callbacks; post-deploy contract migration `2050` removes the old index. Client matching and duplicate detection operate across all connections for a company.

Provider identity and cursor rules:
- `last_synced_at` is the end-to-end high-water mark only when every provider
  page, discovered message, recovery page, and bounded derived summary is
  durable. The owner-fenced nonterminal checkpoint updates `history_id`
  without touching it; terminal completion advances it. Live
  `provider_snapshot_at` is the narrower provider-health high-water mark and
  may advance only when the decoded Gmail/M365 provider cursor is terminal,
  even if derived summary IDs remain. Classification and Phase C retry workers
  also fail closed while `sync_in_progress_at` is nonnull, so an older terminal
  cursor cannot authorize work during assembly of the next snapshot.
- Gmail history expiry takes an overlap from the last successful sync (or connection creation on first setup) and stores a durable recovery triple on `email_connections`: anchor, `messages.list` page token, and fresh target history ID. Each fully persisted page advances the stored continuation, so a gap larger than one function invocation resumes instead of restarting forever. The fresh history ID becomes the normal cursor only after every recovery page and message is durable. Disconnect preserves both provider identity and the prior normal cursor; any incomplete recovery also remains resumable and fails closed rather than skipping the gap.
- Microsoft 365 stores one mail-folder delta plus one message delta/continuation per discovered live folder in a versioned `m365:v2` cursor. A durable pending-folder queue covers Inbox, Sent, Archive, and rule/custom folders under one 50-page cycle budget. The returned cursor becomes durable only after its messages are durable; legacy Inbox/Sent or raw cursors replay a complete folder inventory. Unsent drafts are excluded.
- Every Microsoft Graph message/subscription request asks for `IdType="ImmutableId"`, so moving a message between folders does not change the dedupe identity. Folder/message `@removed` tombstones advance only their proven streams and are not normalized as correspondence. Full-thread reads follow `@odata.nextLink` and fail explicitly if the safety bound is exceeded.
- A sync lease stores both a timestamp and random owner token. Long cycles renew the lease; renewal/release match the owner so a stale worker cannot clear a successor's lock.
- Disconnect is a soft tombstone (`status='disconnected'`, sync disabled, OAuth/webhook secrets cleared) rather than a hard delete. The stable connection row and history cursor remain as provider identity/audit proof; reconnect reuses only that same-provider row.
- Cron sync returns non-2xx when any connection or semantic sweep reports failure. Staleness heartbeat rows are alert-delivery receipts, not positive ingestion receipts: an alert is deduped/logged only when notification or email delivery actually succeeds. If all configured channels fail, the route returns non-2xx and writes no false success receipt so the next run may retry. This still does not prove message completeness; provider-vs-OPS parity requires an independent 48-72 hour anti-join/repair monitor.
- Manual sync uses the same result truth: 200 means terminal completion, 202
  means a durable continuation remains, and an errors array produces retryable
  non-2xx partial/failed state.
- Every application-visible PostgREST RPC identifier must be at most 63 UTF-8
  bytes. PostgreSQL silently truncates longer declarations, which makes an
  untruncated client call permanently unresolvable even when the function body
  exists. Prepared migration
  `20260801003000_fix_contact_form_draft_rpc_identifiers.sql` gives contact-form
  provider-create reservation and uncertain-outcome reconciliation stable
  short service-only names; it delegates to the existing guarded bodies and
  does not replay queue rows or touch provider state.

### OAuth Flow

```
Settings → Integrations → Email
  ├─ authenticated initiation → one-time opaque state → Google OAuth
  └─ authenticated initiation → one-time opaque state → Microsoft OAuth
       callback → verified mailbox identity → email_connections
```

OAuth initiation requires a verified Firebase operator, exact company and user ownership, and `settings.integrations`. The browser-visible `state` contains no tenant context: it is a 256-bit random nonce with a 10-minute lifetime, while `email_oauth_states` stores only its SHA-256 digest plus the server-verified context behind RLS. The callback atomically deletes and returns one unexpired provider-bound row through a service-role-only function, then re-verifies that the returning OPS cookie is the same permitted company/user before token exchange. This browser-session binding blocks relayed-consent mailbox attachment. Expired, replayed, wrong-provider, different/no-session, legacy raw-company, and unsigned base64 state all fail closed. Existing-row lookup errors also fail closed; a callback never treats an unknown read result as a new connection or resets settings by accident. Wizard connects read and upsert only the exact `(company_id, provider, email)` identity.

Alert-email reconnects require OPS login and bind the short-lived state to a server-verified connection ID plus expected normalized mailbox. The confirmation page and provider initiation both re-check that exact connection/company/provider/type/mailbox tuple and require the row to be sync-enabled with status `active` or `needs_reconnect` before displaying tenant identity or issuing consent. Gmail reads the mailbox address from `users/me/profile`; Microsoft requests `User.Read` and reads `/me`. A callback for a different mailbox is rejected. A matching callback re-reads the same eligibility, then compare-and-set updates the exact email/status/sync-enabled snapshot; a stale link cannot resurrect a connection disconnected before or during the callback. Settings and cursor state remain intact. Neither provider may persist a connection without a valid mailbox email.

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

  // Drafts (template follow-up drafts and Phase C drafts)
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
   - Grouped by stage: New Lead, Qualifying, Quoting, Quoted, Follow-Up, Negotiation, Won, Lost, Discarded
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

Terminal actions are conservative:

- High-confidence accepted-work signals may convert the opportunity to a project when the conversion path is configured and the signal is explicit enough.
- Ambiguous win language does nothing. OPS should not create a fake review stage or force a noisy prompt from weak evidence.
- Explicit decline/loss language may move a qualified opportunity to `lost` only when the reason can be recorded with high confidence; otherwise the operator decides.
- If the last meaningful email was inbound and unreplied for more than 30 calendar days, and the lead had moved beyond qualified, it may be marked `lost` with reason `operator_no_response`.
- Won, lost, converted-to-project, and archived opportunities are terminal for stale monitoring.

### 5-Tier Client Matching

**Service:** `src/lib/api/services/email-matching-service.ts` / `email-matching-service-v2.ts`

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

**Important limitation:** client matching is not the same thing as opportunity matching. A repeat customer can have multiple real jobs over time, including at the same address. After a client/contact match, OPS must still decide whether the message belongs to an existing opportunity/project or should create a new opportunity. That decision should consider address, scope, recency, existing opportunity stage, and linked project status. If confidence is not high, create a separate lead and allow the operator to merge it later.

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
2. Generate a random Graph `clientState`, store only its SHA-256 digest, and bind it to the returned subscription id
3. M365 sends change notifications to: `POST /api/integrations/email/webhook/microsoft365`
4. Before any service-role dispatch, reject the entire batch unless every `{subscriptionId, clientState}` matches one active M365 connection
5. Queue the authenticated sync dispatch and return 202; the validation-token handshake still returns plain text 200
6. Subscription expires every 3 days — cron renews every 2 days and recreates any legacy/missing-secret subscription

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
   └── New lead/activity → durably queue the exact-message
       "OPS Pipeline" label/category write before provider access

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

### Cursor-safe deferred recovery (production 2026-07-27)

Classification and pipeline-label recovery are exact-message work, not
thread-wide guesses. The service-only `email_ingestion_recovery_queue` records
the company, active mailbox connection, provider thread, provider message,
recovery kind, and stable operation key before the sync cursor may pass that
work. Forwarded contact forms participate even though their source-bound
message scope deliberately does not create an opportunity-thread relationship.

The email-sync cron claims only work for its current active-subscription company
set. Each retry then acquires the physical-mailbox lease and reauthorizes the
current active, sync-enabled connection immediately before provider access.
Classification fetches the surrounding provider thread for context but replays
only the queued inbound message through the canonical ingestion path. Pipeline
labeling is idempotent per exact message and current label id, because Gmail
does not guarantee that a label already present on earlier thread messages will
appear on a newly arriving message.

Success and failure writes are holder/lease fenced. Failures use bounded
exponential backoff and become explicit terminal records after eight attempts;
they are never reported as success, and an undurable intent or completion holds
the mailbox cursor. Existing provider-message deduplication, immutable lead and
thread ownership, manual classification overrides, authorization gates, and
source-bound contact-form routing remain unchanged.

Assignment-triggered contact-form drafting is scheduled in the ten-minute lead
assignment delivery lane rather than behind attachment/photo maintenance. A
retry must still prove the current assignment, assignee permissions, mailbox,
contact-form source, writing profile, and absence of an existing OPS/provider
draft. Operator escalations and insufficient verified writing examples are
terminal safety holds; transient empty/refused/model-unavailable results retain
the existing durable job and retry under its lease/backoff contract.

Physical-mailbox lease contention is also transient. A `mailbox busy` result
means another OPS path currently owns the shared provider-mailbox safety lease;
it is not evidence that Gmail or Microsoft rejected a draft. Prepared migration
`20260802163538_keep_contact_form_mailbox_busy_retryable.sql` changes the
service-only claim contract to check the canonical physical-mailbox lease before
the bounded batch is selected. A due row is marked waiting once and omitted
while the lease remains active, so it neither consumes worker capacity nor
increments attempts, regenerates model content, or polls the provider. It
resumes automatically after the lease is absent; a post-claim acquisition race
returns to the same wait while preserving its first wait timestamp.

Provider-create uncertainty remains reconciliation-first and a stale assignment
remains terminal. A continuous one-hour wait opens one persistent, deduped
operator notification with no customer identity and resolves it automatically
when the wait lifecycle ends. Exact historical contention failures with null
provider-create markers enter the same guarded wait; assignment, authorization,
reply, terminal-state, autonomy, and prior-draft checks all run again before
provider access. OPS-Web commits `92344a64` and `865bab6e`; prepared but not
applied as of 2026-08-02.

Migration `20260727043334_email_ingestion_recovery_queue` is live before the
compatible application commit `ee3d43db`. The normal path creates no historical
backfill and performs no unsolicited Gmail, draft, or lead-row repair.

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

**Stale/archival target rules:** follow-up and archive rules are opportunity-level, not thread-level. After two unanswered OPS follow-ups, archive 7 calendar days after the second follow-up. Archive opportunities with no meaningful correspondence for 14 calendar days when they are not terminal/protected. If the last meaningful email is inbound and unreplied, treat it as an operator follow-up miss; after 30 calendar days beyond qualified, move to `lost` with reason `operator_no_response`.

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
| Client accepted | High-confidence project conversion, otherwise no action |
| Client declined | High-confidence `lost` with reason, otherwise no action |
| Operator failed to reply > 30 days, beyond qualified | `lost` reason `operator_no_response` |

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

Email threads are linked to opportunities via the `opportunity_email_threads` junction table (not a column on opportunities). This enables fast sync lookup via the unique `(thread_id, connection_id)` mailbox-scoped identity. The first successful owner is immutable; ordinary replies inherit it, while message-scoped contact-form submissions do not create this link. See `03_DATA_ARCHITECTURE.md` for the full schema.

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

Draft learning is based on sent outcomes, not abandoned drafts. The system must retain original generated draft text and final sent text for every draft origin, including template follow-ups and Phase C drafts, so Phase C can learn how the operator actually edits and sends.

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
| Template follow-up draft generation | Yes | Yes |
| Draft provenance and sent-version edit tracking | Yes | Yes, feeds memory |
| Ongoing AI classification per sync | No | `ai_email_review` |
| Ongoing AI stage evaluation per sync | No | `ai_email_review` |
| Win/loss intent detection | Conservative deterministic only | `ai_email_review` improves confidence |
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
- Existing opportunities are checked first, but client match alone is not enough; same-client/same-address messages may still be separate jobs when prior work is closed or scope differs
- If matching confidence is not high, create a separate lead and provide an operator merge path instead of over-linking
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
| Discarded | `discarded` | User marks lead as not worth pursuing | Terminal — ad quality signal |

### Project Statuses

| Status | Meaning | Set When |
|---|---|---|
| `RFQ` | Request for Quote — project stub created, no estimate yet | Project auto-created at estimate send |
| `Estimated` | At least one estimate has been sent | Estimate sent |
| `Accepted` | Estimate approved, work authorized | Estimate approved |
| `InProgress` | Field work started | First task goes InProgress |
| `Completed` | All tasks done, ready to invoice | All tasks Completed |
| `Closed` | Complete **and** fully paid — terminal *success* | All tasks Completed **and** invoice status → Paid (auto, Automation F) |
| `Archived` | Paused or cancelled — work will not continue | Operator action only — **never** an automatic post-completion state |

> **Closed vs Archived (canonical rule).** `Closed` is the terminal *success* state — the job finished and the money is in. `Archived` is the terminal *non-completion* state — work that was paused or cancelled. Completion never auto-archives: a completed, fully-paid project moves to `Closed`; `Archived` is reserved for operator-initiated pause/cancel. Any automation that archives a completed+paid project is a defect — it must move the project to `Closed` (see the web-correction note under Automation F).

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

### Supabase Tables — status (site-visit contract verified 2026-08-02)

The list below was originally written as "tables needed." A live audit on 2026-05-10 found `project_photos` already exists in production — schema and use documented below. Other tables in this list may also be stale; a full audit is a separate follow-up.

```sql
-- activity_comments               (status TBD)
-- site_visits                     EXISTS IN PROD (company_id is text)
-- site_visit_artifacts            EXISTS IN PROD (company_id text; Realtime; RLS)
-- site_visit_checklist_answers    EXISTS IN PROD (company_id text; Realtime; RLS)
-- site_visit_identity_drafts      EXISTS IN PROD (company_id text; Realtime; RLS)
-- site_visit_types                EXISTS IN PROD 2026-08-06 (migration 20260806211208; company_id text; Realtime; RLS)
-- project_photos                  EXISTS IN PROD — see schema below
-- email_connections               (renamed from gmail_connections, status TBD)
-- opportunity_email_threads       (status TBD)
-- admin_feature_overrides         (status TBD)
-- agent_memories                  (feature-gated, status TBD)
-- agent_knowledge_graph           (feature-gated, status TBD)
-- agent_writing_profiles          (feature-gated, status TBD)
-- company_settings                (status TBD — alter if table exists)
```

**`project_photos` actual schema (verified live 2026-05-10):**

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `project_id` | text | NO | — |
| `company_id` | text | NO | — |
| `url` | text | NO | — |
| `thumbnail_url` | text | YES | — |
| `source` | enum `photo_source` (`site_visit`, `in_progress`, `completion`, `other`, `measurement`, `deck_design`, `email`) | NO | `'other'` |
| `site_visit_id` | uuid | YES | — |
| `uploaded_by` | text | NO | — |
| `taken_at` | timestamptz | YES | — |
| `caption` | text | YES | — |
| `is_client_visible` | boolean | NO | `false` |
| `created_at` | timestamptz | YES | `now()` |
| `deleted_at` | timestamptz | YES | — |
| `email_attachment_id` | uuid → `email_attachments(id)` `on delete set null` | YES | — |
| `origin_sender_email` | text | YES | — |

`source = 'measurement'` is used by LiDAR Dimensioned Photo Capture (see §07 Section 23) — added 2026-05-10 alongside the spec. `source = 'deck_design'` remains accepted for iOS deck builder thumbnails and photo overlay captures.

`source = 'email'` (enum value added 2026-08-18, ledger `20260818053040`) marks photos published by the email→project conversion pipeline. The two provenance columns (ledger `20260818053050`, indexed by `project_photos_email_attachment_idx` where non-null) are written **only** by that pipeline — never by a manual upload, on any surface. Both are nullable and additive, so deployed iOS builds and the deployed web bundle ignore them. Nothing writes `source='email'` yet: the completion-function flip and the 12-row backfill are staged until the ops-web `main` push GO (see Automation E2 above).

### Projects Table V2 Phase 1 Schema Foundation (added 2026-05-12)

Phase 1 of the Projects table redesign is schema-only. It does not change the current `/projects` UI, but it establishes the saved-view and read-model layer behind the future `projects_table_v2` flag.

- `project_views` stores company and user saved table views. Each row carries the column layout, filters, sort, density, zoom, optional `permission_key`, and RLS-scoped ownership. Default company views are seeded for existing companies and for newly inserted companies.
- `project_table_rows` is the security-invoker read view for the table surface. It denormalizes project, client, task progress, next task, days in status, photo count, and financial aggregates into one wire shape.
- `projects.team_member_ids` is a denormalized cache of non-deleted `project_tasks.team_member_ids`. It is not a free-floating project assignment list. The `project_tasks_sync_project_team_member_ids` trigger recomputes the cache after task insert/delete and after updates to `team_member_ids`, `deleted_at`, or `project_id`.
- `assign_project_team_member`, `remove_project_team_member`, and `change_project_status` are the Phase 1 public RPCs for atomic table writes. They validate inputs, enforce scoped project permissions through private helpers, use `updated_at` as the conflict token, and return the fresh wire state needed by the table cache.
- Financial table fields (`estimate_total`, `invoice_total`, `paid_total`, `value`, `project_cost`, `margin`) are gated at the SQL wire level. Without `projects.view_financials`, `project_table_rows` returns `null`, never zero; clients render the empty-state mark.

### Projects Table V2 Phase 2 Read-Only UI (added 2026-05-12)

Phase 2 renders the new Projects spreadsheet behind the per-user `projects_table_v2` component flag. The UI reads `project_views` for seeded saved views and `project_table_rows` for the virtualized read model. It is read-only: status changes, team assignment, inline editing, undo, and conflict handling remain outside this phase. The default load excludes closed and archived projects through the seeded saved-view filters; operators can still switch views without touching the legacy canvas.

OPS-Web browser sessions use Firebase JWTs as the Supabase `accessToken`, so PostgREST evaluates them as the `anon` database role while RLS resolves the OPS user through `private.get_current_user_id()`. The Phase 2 Firebase bridge grants `anon` `SELECT` only on `project_views` and `project_table_rows`; `project_views` keeps only its read policy on `to public`, while saved-view manage policies and table mutation RPC execute grants remain authenticated-only.

### Projects Table V2 Phase 3 Edit Core (added 2026-05-13)

Projects Table V2 now supports inline edits for core project fields: title, address, start date, end date, and status. Direct project-field edits use PostgREST updates against `public.projects` with an `updated_at` equality check; zero-row updates are treated as edit conflicts. Status changes use `public.change_project_status(...)`, which preserves the canonical `project_notes.event_kind = 'status_change'` activity trail.

Undo is client-side and capped at 50 entries. Undo performs a real reverse write through the same direct-update/RPC path and therefore respects current permissions and conflict tokens. The browser Firebase bridge uses the `anon` database role, so the restrictive `projects.role_scope_update` policy applies to `public`, and `anon` can execute only the status RPC from the Phase 1 RPC family.

### Projects Table V2 Phase 4 Complex Cells + Bulk Writes (added 2026-05-13)

Phase 4 is the OPS-Web shipped path for complex table cells and bulk writes: task-backed team assignment, Storage-backed table photo uploads, selection-aware bulk status/team/date changes, partial-failure retry, and one client undo entry per successful bulk operation.

Team cells are canonical through task-backed membership only. OPS-Web table assignment must call `create_project_table_assignment_task`, `assign_project_team_member`, or `remove_project_team_member`; it must not insert `project_tasks` directly and must not write `projects.team_member_ids`. Those RPCs, plus `bulk_update_project_table`, are executable by the Firebase bridge (`anon`) and authenticated clients because Firebase browser sessions arrive at PostgREST as `anon`. That exposure is intentional: every function is helper-gated with scoped project permissions, company isolation, parseable IDs, and `updated_at` conflict checks before writing.

iOS direct task creation and task-level team assignment remain supported for the existing queued Firebase/Supabase bridge. `anon` has direct `INSERT` on `public.project_tasks`, and RLS requires the inserted company to match the current OPS user, the user to hold `tasks.create` with `all` scope, and the target `project_id` to resolve to a non-deleted project in the same company. Direct `DELETE` on `project_tasks` stays revoked for `anon`. Project-level iOS crew edits use the same helper-gated assignment RPCs as the table path, creating a task-backed assignment row when no active task exists.

`projects.team_member_ids` remains server-derived from non-deleted `project_tasks.team_member_ids` through the `project_tasks_sync_project_team_member_ids` trigger. It is not a client-owned assignment list and should not be directly written by new clients.

Phase 4 project photo hardening keeps direct `project_photos` insert/update compatibility for valid edit-capable users while denying hard deletes. Storage writes for `project-photos` are scoped by bucket path, company, parseable project id, and `private.current_user_can_edit_project(...)`; table uploads use the path `<company_id>/<project_id>/<uuid>.<ext>`. Table uploads write `project_photos.source = 'other'`, and `uploaded_by` is the public `users.id` for the current OPS user. Table upload hooks also mirror successful uploads to `project_notes.event_kind = 'photo_uploaded'` on a best-effort basis so timeline failure never fails the gallery upload. The `deck_design` `photo_source` value is accepted for iOS deck builder compatibility.

`bulk_update_project_table` accepts visible-row operations only from the client and returns per-project `success` and `failed` arrays with counts. Successful rows are applied to the table cache and included in a single bulk undo entry; failed rows remain selected for Retry or Discard. Bulk undo performs a fresh reverse `bulk_update_project_table` call with the saved post-change conflict tokens, so undo remains permission-checked and conflict-aware.

### Projects Table V2 Phase 5 Saved Views + Density (added 2026-05-14)

Phase 5 adds saved-view management and density persistence for the OPS-Web Projects spreadsheet. The live migration is `20260514163406_projects_table_v2_phase5_saved_view_actions.sql`; generated database types include the saved-view RPC contracts.

Saved views have two ownership modes. Personal views use `project_views.owner_type = 'user'` with `owner_id` set to the current OPS user. Company views use `owner_type = 'company'` with `owner_id` set to the company id and are visible to the company subject to any `permission_key`. Creating or duplicating a view always creates a personal view first. Sharing a view with the team converts it to company ownership and requires `projects.manage_views`.

OPS-Web must mutate saved views only through the Phase 5 RPCs: `create_project_table_view`, `rename_project_table_view`, `archive_project_table_view`, `reset_project_table_view`, `share_project_table_view`, and `update_project_table_view_definition`. Clients must not issue direct `project_views` update/delete writes for saved-view management. The RPCs sanitize names and definitions, enforce company isolation, enforce owner permissions, and keep Firebase browser sessions working through the `anon` execute grants while still checking the current OPS user inside the function.

Archive is soft delete. `archive_project_table_view` sets `project_views.is_archived = true`; it does not hard delete the row. Archived views are removed from normal view lists and are not considered accessible for active view selection or deep links.

The persisted view definition is the contract for table layout and density. The server accepts only `columns`, `filters`, `sort`, `density`, and `zoom_level` definition keys. These persist back to `project_views.columns`, `project_views.filters`, `project_views.sort`, `project_views.density`, and `project_views.zoom_level`. Default reset recomputes those fields from the canonical server default definition for the selected default view.

The Projects route supports saved-view deep links through `?view=<id>`. A valid, accessible, non-archived view id becomes the active view and is stored as the user's last selected view. If the URL points to an invalid, archived, or inaccessible view, OPS-Web falls back to the default accessible view, stores that fallback, and replaces the URL with the fallback `?view=<id>` instead of rendering a broken table state.

Density has three persisted presets: compact `0.85`, comfortable `1.00`, and spacious `1.25`. The density controls, keyboard shortcuts, pinch gestures, and Ctrl/Meta-wheel gestures update table metrics - row height, header height, font sizes, avatar size, and column scale - and then persist the nearest density/zoom pair through `update_project_table_view_definition`. The table must not use CSS `transform: scale(...)` for density changes; scaling is metric-driven so hit targets, virtualization, text layout, and column math stay coherent.

`projects.manage_views` gates company/share behavior. Users without it may manage their own personal saved views but must not see or execute team-share controls, and they cannot mutate company-owned views. `projects.view_financials` continues to gate the Financial Overview view and all financial data. The Financial Overview saved view remains protected by `permission_key = 'projects.view_financials'`, and the `project_table_rows` financial fields still return `null` at the SQL wire level when the user lacks that permission.

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

#### SiteVisit — iOS capture and durable sync (database live 2026-08-02; iOS distribution pending)

The `SiteVisit` data model exists at `ops-ios/OPS/DataModels/Supabase/SiteVisit.swift`; `opportunityId` is optional so the FAB can start capture before a lead is selected. Lead detail, New Lead, and the FAB open a full-screen capture console from `ops-ios/OPS/Views/SiteVisits/`. The normalized database contract and guarded completion path are live in production. The updated iOS client is committed and simulator-verified but is not customer-distributed until its signed physical-device/App Store release gate completes.

Built iOS files:

| File | Purpose |
|---|---|
| `SiteVisitIdentityDraft.swift` | SwiftData model for local-first client/lead identity capture: client/contact/address/search fields, additional emails, linked client/opportunity ids, and completion state |
| `SiteVisitCaptureView.swift` | Field-first capture console: inline lead/client search + manual identity fields, rapid photos, autosaved dictated/typed notes, measurements, dimensioned capture, photo thumbnails/preview/markup, gated deck-design capture, packet review |
| `SiteVisitCaptureViewModel.swift` | Creates/reuses an active visit, seeds/selects visit types, snapshots checklist answers, autosaves identity and note drafts, creates/links lead/client records, saves local artifacts, links captured evidence to checklist answers, reassigns packets to another lead, completes the visit, builds the reviewed project payload |
| `SiteVisitDimensionedCaptureStore.swift` | Saves pre-project `CapturedAssets` + `DimensionsData` as a local dimensioned-photo artifact |
| `SiteVisitProjectHandoff.swift` | Applies reviewed artifacts to a newly created project as `ProjectPhoto`, dimensioned `PhotoAnnotation`, `ProjectNote`, and attached `DeckDesign` rows — each with a durable sync path (photos enter `ImageSyncManager`'s restart-surviving upload queue and heal `local://`→S3 in place; deck links record a `deckDesign` update SyncOperation). Also `derivePayload`, which rebuilds the packet from persisted rows when the staging store was lost (see § 22B in 03_DATA_ARCHITECTURE) |
| `SiteVisitProjectHandoffStore.swift` | In-memory fast path staging the reviewed packet between the review sheet and the conversion sheet; when it is empty at conversion (app kill in between), the sheet falls back to `SiteVisitProjectHandoff.derivePayload` |
| `SiteVisitCaptureArtifact.swift` | SwiftData model for the local pre-project packet and reviewed project payload |
| `SiteVisitType.swift` | SwiftData models for company-scoped visit templates, custom fields, and per-visit checklist answer snapshots |
| `Views/Settings/SiteVisitTypeSettingsView.swift` | Company checklist list/editor: create/default, field kind, order, required, show/hide, soft delete |
| `Views/SiteVisits/SiteVisitChecklistGuideView.swift` | First-eligible-open Settings pointer with user-scoped never-show-again persistence |
| `Network/Supabase/DTOs/SiteVisitTypeDTOs.swift` | Strict wire representation for shared checklist templates |
| `Network/Supabase/Repositories/SiteVisitTypeRepository.swift` | Company-scoped template fetch/upsert/update/tombstone transport |
| `Network/Sync/SiteVisitTypeServerMerge.swift` | Shared pending-write-preserving full-pull/delta/Realtime merge |
| `Network/Supabase/DTOs/SiteVisitDTOs.swift` | Strict UUID/status/wire conversion for parent and normalized child tables plus completion response |
| `Network/Supabase/Repositories/SiteVisitRepository.swift` | Company-scoped CRUD, bundle fetch, sparse parent updates, and guarded completion RPC |
| `Services/SiteVisitPersistenceCoordinator.swift` | One local transaction for state + parent-first durable operation chain |
| `Network/Sync/SiteVisitOutboundSync.swift` | Typed operation dispatcher and server ACK reconciliation |
| `Network/Sync/SiteVisitMediaSyncManager.swift` | Restart-safe original/rendered/thumbnail upload through the visit-authorized presign contract; oversized-only outbound preparation enforces the 10 MiB / 2,048 px boundary without overwriting originals |
| `Network/Sync/SiteVisitServerMerge.swift` | Dirty-field-preserving inbound merge and authoritative terminal-state reconciliation |
| `Network/Sync/SiteVisitOrphanRecovery.swift` | Same-company legacy parent reconstruction; foreign/malformed/ambiguous quarantine |
| `Network/Sync/SiteVisitRecoveryVault.swift` | AES-GCM, exact-account, phone-local custody across forced logout and guarded requeue after authoritative restored-parent proof |
| `Network/Sync/DeletedProjectTaskOperationSettlement.swift` | Retires only a parked server-row-missing task update whose exact same-company local row is already a soft-delete tombstone |

The site-visit measure-photo action now uses the real dimensioned capture/annotation screen when `feature.measurement.dimensioned_capture` and device capability allow it. Simulator and no-AR devices still cannot validate LiDAR hardware capture; physical-device QA is required before claiming the scanner is field-proven.

#### Email Pipeline Integration — Web-Owned; iOS Follow-Up Client Added 2026-07-23

Email integration API routes exist on the web backend (`OPS-Web/src/app/api/integrations/email/`):
- `route.ts` — main email integration endpoint
- `callback/route.ts` — OAuth callback handler (Gmail + M365)
- `sync/route.ts` — sync trigger
- `webhook/gmail/route.ts` — Gmail Pub/Sub webhook receiver
- `webhook/microsoft365/route.ts` — M365 Change Notifications webhook receiver

Supporting web services: `email-service.ts`, `email-sync-service.ts`, `email-matching-service.ts`, `email-classifier.ts`, `use-email-connections.ts`, `email-setup-wizard.tsx`.

iOS still does not connect to or sync email accounts and does not expose the web inbox. It reads the shared `opportunities` state and now calls the narrow authenticated `POST /api/leads/:opportunityId/follow-up` path from Due/Overdue lead chase controls. OPS-Web remains the sole owner of mailbox authorization, provider threading, message content/signature, delivery, and reconciliation; see **One-Tap Lead Follow-Up (iOS + OPS-Web, 2026-07-23)** above.

#### In-App Email Client (Web — Built 2026-03-19)

The web app includes a full in-app email client at `/inbox` (inbox view, compose modal, email templates, AI drafting with 3-phase progression, auto-send, and stage manual override). Sync engine hardened with subscription gating, activity data enrichment, timestamp validation, and OpenAI API key separation across three keys (import/sync/drafting). See `07_SPECIALIZED_FEATURES.md` §19 for the complete in-app email system documentation.

---

### Email activity -> canonical file -> lead/project lifecycle (prepared 2026-07-15)

1. Inbound or outbound sync persists one exact provider-backed email activity and its correspondence projection.
2. The activity trigger upserts one generation-fenced `email_attachment_scans` job. Attachment work is not cursor-critical.
3. A bounded worker enumerates that immutable provider message, records every descriptor, validates the activity's current lead identity, copies supported bytes into private OPS storage, verifies size/hash/MIME, and refreshes stable activity attachment URLs.
4. A separate inspection job reads only stored bytes. Signed-estimate/acceptance evidence may update the current lead only after exact attribution is re-checked.
5. Reassignment or merge clears stale attribution and increments job generations. A worker holding an older generation cannot commit ownership to either the old or newly assigned lead.
6. Won conversion retains access through `projects.opportunity_id`; no duplicate storage copy or lossy photo-array move is required.

Unknown or mismatched identity remains activity-scoped `needs_review` and is absent from lead/project photo surfaces. Disconnected mailboxes resume queued work after reconnect. Stored OPS copies remain accessible after provider deletion or disconnect.

*This document supersedes any prior informal notes about entity relationships. All implementation decisions should reference this document.*
