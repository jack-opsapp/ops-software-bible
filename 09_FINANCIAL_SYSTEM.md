# 09_FINANCIAL_SYSTEM.md

**OPS Software Bible - Pipeline, Estimates, Invoices & Financial Architecture**

**Purpose**: Complete documentation of the OPS financial system — pipeline/CRM, estimates, invoices, payments, products catalog, and accounting integrations. All financial data lives in **Supabase** (PostgreSQL), separate from operational data in Bubble.io.

**Last Updated**: February 17, 2026
**Source Reference**: `C:\OPS\ops-web\src\lib\types\pipeline.ts`, `src\lib\api\services\`

---

## Table of Contents

1. [Dual-Database Architecture](#dual-database-architecture)
2. [Pipeline / CRM System](#pipeline--crm-system)
3. [Estimates System](#estimates-system)
4. [Invoices System](#invoices-system)
5. [Products & Services Catalog](#products--services-catalog)
6. [Payments](#payments)
7. [Accounting Integrations](#accounting-integrations)
8. [Activity Timeline & Follow-Ups](#activity-timeline--follow-ups)
9. [Supabase Schema Reference](#supabase-schema-reference)
10. [Service Layer Patterns](#service-layer-patterns)
11. [Business Rules & Constraints](#business-rules--constraints)

---

## Dual-Database Architecture

OPS Web uses two separate backends for different data domains:

| Data Domain | Backend | Rationale |
|---|---|---|
| Projects, Tasks, Clients | Bubble.io REST API | Shared with iOS/Android apps |
| Calendar Events, Company, Users | Bubble.io REST API | Shared with iOS/Android apps |
| Pipeline Opportunities | Supabase (PostgreSQL) | Relational, real-time, complex queries |
| Estimates, Invoices, Line Items | Supabase (PostgreSQL) | Financial data, needs DB triggers |
| Products Catalog | Supabase (PostgreSQL) | Per-company catalog |
| Payments | Supabase (PostgreSQL) | Insert-only, trigger-maintained balances |
| Accounting Connections | Supabase (PostgreSQL) | OAuth token storage |
| Tax Rates | Supabase (PostgreSQL) | Per-company tax config |
| Pipeline Stage Config | Supabase (PostgreSQL) | Per-company customization |

**Env vars required for Supabase:**
```
NEXT_PUBLIC_SUPABASE_URL=<supabase project url>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<supabase anon key>
```

**Client helper** (`src/lib/supabase/helpers.ts`):
- `requireSupabase()` — returns Supabase client, throws if env vars missing
- `parseDate(val)` — parses nullable date string → `Date | null`
- `parseDateRequired(val)` — parses required date string → `Date`

---

## Pipeline / CRM System

### Overview

The pipeline tracks leads from first contact through to a won/lost outcome and project conversion. It is a Kanban-style board using `@dnd-kit` for drag-and-drop.

### Pipeline Stages

8 ordered stages, divided into **active** and **terminal**:

| Stage | Slug | Color | Win Probability | Auto Follow-Up |
|---|---|---|---|---|
| New Lead | `new_lead` | #BCBCBC | 10% | 2 days |
| Qualifying | `qualifying` | #8195B5 | 20% | 3 days |
| Quoting | `quoting` | #C4A868 | 40% | 3 days |
| Quoted | `quoted` | #B5A381 | 60% | 5 days |
| Follow-Up | `follow_up` | #A182B5 | 50% | 3 days |
| Negotiation | `negotiation` | #B58289 | 75% | 2 days |
| **Won** | `won` | #9DB582 | 100% | — |
| **Lost** | `lost` | #6B7280 | 0% | — |

Active stages (NewLead → Negotiation) appear as standard columns. Won and Lost are terminal columns separated by a visual divider on the board.

Per-company stage configuration is stored in the `pipeline_stage_configs` table, seeded from `PIPELINE_STAGES_DEFAULT`.

### Opportunity Entity

```typescript
interface Opportunity {
  id: string;
  companyId: string;
  clientId: string | null;       // Link to Bubble client (optional - leads may not have a client yet)
  title: string;
  description: string | null;

  // Contact info for leads without a client record
  contactName: string | null;
  contactEmail: string | null;
  contactPhone: string | null;

  // Pipeline tracking
  stage: OpportunityStage;
  source: OpportunitySource | null;  // referral | website | email | phone | walk_in | social_media | repeat_client | other
  assignedTo: string | null;         // User ID
  priority: OpportunityPriority | null; // low | medium | high

  // Financial
  estimatedValue: number | null;
  actualValue: number | null;
  winProbability: number;           // 0-100

  // Dates
  expectedCloseDate: Date | null;
  actualCloseDate: Date | null;
  stageEnteredAt: Date;

  // Conversion
  projectId: string | null;         // Set when Won and converted to project
  lostReason: string | null;        // One of LOSS_REASONS
  lostNotes: string | null;

  address: string | null;

  // Denormalized
  lastActivityAt: Date | null;
  nextFollowUpAt: Date | null;
  tags: string[];

  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

### Pipeline Board UI

**Component**: `src/app/(dashboard)/pipeline/_components/pipeline-board.tsx`

- Uses `@dnd-kit/core` with `PointerSensor` (8px activation distance)
- `closestCorners` collision detection
- `DragOverlay` renders ghost card during drag
- Active stages render as `PipelineColumn` components
- Terminal stages (Won/Lost) are narrower, no "Add Lead" button
- Board filters: search (title, contact name, client name) + stage filter

**Drag behavior:**
- `handleDragStart` → sets activeId, shows overlay
- `handleDragEnd` → calls `onMoveStage(opportunityId, newStage)`
- Stage validation: target must be in `ALL_BOARD_STAGES`
- No-op if moved to same stage

### Opportunity Helpers

```typescript
// Stage navigation
nextOpportunityStage(current)       // Returns next stage or null
previousOpportunityStage(current)   // Returns previous stage or null
isActiveStage(stage)                // true for NewLead→Negotiation
isTerminalStage(stage)              // true for Won/Lost
getActiveStages()                   // Returns [NewLead..Negotiation]
getAllStages()                       // Returns all 8 stages

// Card data
getWeightedValue(opportunity)       // estimatedValue * winProbability / 100
isOpportunityStale(opportunity, thresholdDays=7)  // true if no activity within threshold
getDaysInStage(opportunity)         // Days since stageEnteredAt
getOpportunityContactName(opp, client?)  // client.name ?? contactName ?? "Unknown Contact"

// Loss prompt
LOSS_REASONS = ["Price", "Timing", "Competition", "Scope", "No Response", "Other"]
```

### Stage Transitions

Each stage change records an immutable `StageTransition` row:

```typescript
interface StageTransition {
  id: string;
  companyId: string;
  opportunityId: string;
  fromStage: OpportunityStage | null;
  toStage: OpportunityStage;
  transitionedAt: Date;
  transitionedBy: string | null;   // User ID
  durationInStage: number | null;  // Milliseconds in previous stage
}
```

### OpportunityService

Located at `src/lib/api/services/opportunity-service.ts` (wired from `2742b60` commit):
- `fetchOpportunities(companyId, options)` — filter by stage, includeDeleted
- `fetchOpportunity(id)` — with activities, followUps, stageTransitions
- `createOpportunity(data)` — auto-sets stageEnteredAt
- `updateOpportunity(id, data)` — records stage transition if stage changed
- `deleteOpportunity(id)` — soft delete via deleted_at
- `moveToStage(id, newStage, userId)` — wraps updateOpportunity, records transition
- `markWon(id, actualValue, projectId?)` — sets Won + actualCloseDate
- `markLost(id, lostReason, lostNotes?)` — sets Lost + actualCloseDate

---

## Estimates System

### Estimate Lifecycle

```
Draft → Sent → Viewed → Approved → Converted (to Invoice)
              ↓
         ChangesRequested → (back to Draft)
         Declined
         Expired (auto when expirationDate passes)
         Superseded (when a new version replaces it)
```

### Estimate Entity

```typescript
interface Estimate {
  id: string;
  companyId: string;
  opportunityId: string | null;   // Link to pipeline opportunity
  clientId: string;               // Required - Bubble client ID
  estimateNumber: string;         // Auto-generated via Supabase RPC (e.g. "EST-0001")
  version: number;                // Revision number, starts at 1
  parentId: string | null;        // Reference to previous version

  // Content
  title: string | null;
  clientMessage: string | null;   // Customer-facing message
  internalNotes: string | null;   // Internal notes only
  terms: string | null;           // Terms and conditions text

  // Pricing (snapshots - pre-calculated, not computed at query time)
  subtotal: number;
  discountType: DiscountType | null;  // "percentage" | "fixed"
  discountValue: number | null;
  discountAmount: number;
  taxRate: number | null;         // e.g. 0.0875 for 8.75%
  taxAmount: number;
  total: number;

  // Payment schedule (deposit)
  depositType: DiscountType | null;
  depositValue: number | null;
  depositAmount: number | null;

  // Status tracking
  status: EstimateStatus;
  issueDate: Date;
  expirationDate: Date | null;
  sentAt: Date | null;
  viewedAt: Date | null;
  approvedAt: Date | null;

  pdfStoragePath: string | null;

  createdBy: string | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // Loaded separately
  lineItems?: LineItem[];
  paymentMilestones?: PaymentMilestone[];
  client?: Client | null;
  opportunity?: Opportunity | null;
}
```

### EstimateService

Located at `src/lib/api/services/estimate-service.ts`:

- `fetchEstimates(companyId, options)` — filter by status, clientId, opportunityId
- `fetchEstimate(id)` — includes line items (ordered by sort_order)
- `createEstimate(data, lineItems[])` — two-step: RPC for estimate number, then insert header + line items
- `updateEstimate(id, data, lineItems?)` — if lineItems provided, delete-all-and-reinsert
- `deleteEstimate(id)` — soft delete via deleted_at
- `sendEstimate(id)` — sets status=Sent, sent_at=now
- `convertToInvoice(estimateId, dueDate?)` — **atomic Supabase RPC** `convert_estimate_to_invoice`

### Document Number Generation

Estimate and invoice numbers are generated server-side via Supabase RPC:

```sql
-- RPC: get_next_document_number(p_company_id, p_document_type)
-- Returns: "EST-0001", "EST-0002", ... or "INV-0001", "INV-0002", ...
```

This ensures sequential, race-condition-free numbering per company.

### Estimate Helpers

```typescript
isEstimateExpired(estimate)     // true if past expirationDate and not Approved/Converted
isEstimateEditable(estimate)    // true only for Draft or ChangesRequested
isEstimateSendable(estimate)    // true only for Draft
```

### Line Items

```typescript
interface LineItem {
  id: string;
  companyId: string;
  estimateId: string | null;    // Exactly one of these must be set
  invoiceId: string | null;

  productId: string | null;     // Optional reference to Products catalog

  // Content
  name: string;
  description: string | null;
  quantity: number;
  unit: string;                 // "each" | "hour" | "sqft" | "linear ft" | "day" | "flat rate"
  unitPrice: number;
  unitCost: number | null;      // For margin tracking
  discountPercent: number;      // 0-100
  isTaxable: boolean;
  taxRateId: string | null;

  lineTotal: number;            // GENERATED ALWAYS by DB: qty * unitPrice * (1 - discountPercent/100)

  // Estimate-specific
  isOptional: boolean;          // Optional line items client can include/exclude
  isSelected: boolean;          // Whether optional item is selected

  sortOrder: number;
  category: string | null;
  serviceDate: Date | null;

  createdAt: Date | null;
}
```

**Critical**: `line_total` is a `GENERATED ALWAYS` column — **never include in INSERT/UPDATE**.

### Payment Milestones

For progress billing on estimates:

```typescript
interface PaymentMilestone {
  id: string;
  estimateId: string;
  name: string;                 // e.g. "Deposit", "Upon Completion"
  type: MilestoneType;          // "percentage" | "fixed"
  value: number;                // Percentage (0-100) or fixed amount
  amount: number;               // Calculated dollar amount
  sortOrder: number;
  invoiceId: string | null;     // Set when milestone is invoiced
  paidAt: Date | null;
}
```

### Line Item Calculation Helpers

```typescript
calculateLineTotal(qty, unitPrice, discountPercent?)
// = qty * unitPrice * (1 - discountPercent/100), rounded to 2 decimals

calculateLineTax(lineTotal, taxRate)
// = lineTotal * taxRate, rounded to 2 decimals

calculateDocumentTotals(lineItems[], taxRate?, discountAmount?)
// Returns { subtotal, taxAmount, total }
// Only includes selected items (isOptional=false OR isSelected=true)

calculateMargin(unitPrice, unitCost)
// Returns profit margin as percentage, null if no unitCost

formatCurrency(amount, currency?)     // "USD" default → "$1,234.56"
formatTaxRate(rate)                   // 0.0875 → "8.75%"
```

---

## Invoices System

### Invoice Lifecycle

```
Draft → Sent → AwaitingPayment → PartiallyPaid → Paid
                                ↓
                              PastDue → Paid | WrittenOff
     → Void (from any status)
```

### Invoice Entity

```typescript
interface Invoice {
  id: string;
  companyId: string;
  clientId: string;
  estimateId: string | null;      // Set if converted from estimate
  opportunityId: string | null;   // Link to pipeline opportunity
  projectId: string | null;       // Link to Bubble project
  invoiceNumber: string;          // Auto-generated via RPC (e.g. "INV-0001")

  // Content
  subject: string | null;
  clientMessage: string | null;
  internalNotes: string | null;
  footer: string | null;
  terms: string | null;

  // Pricing
  subtotal: number;
  discountType: DiscountType | null;
  discountValue: number | null;
  discountAmount: number;
  taxRate: number | null;
  taxAmount: number;
  total: number;

  // Payment tracking (maintained by DB trigger — NEVER update manually)
  amountPaid: number;
  balanceDue: number;
  depositApplied: number;

  // Status & dates
  status: InvoiceStatus;
  issueDate: Date;
  dueDate: Date;
  paymentTerms: string | null;    // "Net 30", "Due on Receipt", etc.
  sentAt: Date | null;
  viewedAt: Date | null;
  paidAt: Date | null;

  pdfStoragePath: string | null;

  createdBy: string | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

### InvoiceService

Located at `src/lib/api/services/invoice-service.ts`:

- `fetchInvoices(companyId, options)` — filter by status, clientId, projectId, opportunityId
- `fetchInvoice(id)` — includes line items and non-voided payments
- `createInvoice(data, lineItems[])` — RPC for invoice number, then insert header + line items
- `updateInvoice(id, data, lineItems?)` — replace line items if provided
- `deleteInvoice(id)` — soft delete via deleted_at
- `sendInvoice(id)` — sets status=Sent, sent_at=now
- `voidInvoice(id)` — sets status=Void
- `recordPayment(data)` — insert into `payments` table; DB trigger updates invoice balance
- `fetchInvoicePayments(invoiceId)` — non-voided payments, desc by date
- `voidPayment(paymentId, userId)` — sets voided_at + voided_by; DB trigger recalculates balance

### Invoice Payment Balance (DB Triggers)

The `amount_paid`, `balance_due`, and `status` on invoices are **maintained by Supabase DB triggers**. Do NOT update them manually. The flow:

1. Insert a `payment` row → trigger recalculates `amount_paid`, `balance_due`, updates status (PartiallyPaid / Paid)
2. Void a payment (set `voided_at`) → trigger recalculates again
3. Never call `updateInvoice` to change payment amounts

### Invoice Helpers

```typescript
isInvoiceOverdue(invoice)    // true if past dueDate, balance > 0, not Paid/Void/WrittenOff
isInvoicePayable(invoice)    // true if balance > 0 and not Draft/Void/WrittenOff
getDaysUntilDue(invoice)     // Negative = overdue, positive = days remaining
```

### Payment Entity

```typescript
interface Payment {
  id: string;
  companyId: string;
  invoiceId: string;
  clientId: string;
  amount: number;
  paymentMethod: PaymentMethod | null;  // credit_card | debit_card | ach | cash | check | bank_transfer | stripe | other
  referenceNumber: string | null;       // Check number, transaction ID, etc.
  notes: string | null;
  paymentDate: Date;
  stripePaymentIntent: string | null;   // For Stripe payments
  createdBy: string | null;
  createdAt: Date;
  voidedAt: Date | null;               // NOT deleted_at — use voided_at for voiding
  voidedBy: string | null;
}
```

### Payment Terms Options

```
"Due on Receipt", "Net 7", "Net 10", "Net 15", "Net 30", "Net 45", "Net 60", "Net 90"
```

---

## Products & Services Catalog

### Product Entity

```typescript
interface Product {
  id: string;
  companyId: string;
  name: string;
  description: string | null;
  defaultPrice: number;
  unitCost: number | null;        // For profit margin tracking
  unit: string;                   // "each" | "hour" | "sqft" | "linear ft" | "day" | "flat rate"
  category: string | null;        // Custom grouping
  isTaxable: boolean;
  isActive: boolean;
  createdAt: Date | null;
  updatedAt: Date | null;
  deletedAt: Date | null;
}
```

Products are soft-deleted. `ProductService.fetchProducts(companyId, activeOnly=true)` returns only active, non-deleted products by default.

Line items can reference a product via `productId`. When a product is selected from the catalog, it pre-fills the line item name, description, unit price, unit cost, unit, and taxable flag.

---

## Accounting Integrations

### AccountingConnection Entity

```typescript
interface AccountingConnection {
  id: string;
  companyId: string;
  provider: AccountingProvider;   // "quickbooks" | "sage"
  accessToken: string | null;     // OAuth access token
  refreshToken: string | null;    // OAuth refresh token
  tokenExpiresAt: Date | null;
  realmId: string | null;         // QuickBooks realm/company ID
  isConnected: boolean;
  lastSyncAt: Date | null;
  syncEnabled: boolean;
  webhookVerifierToken: string | null;
  createdAt: Date | null;
  updatedAt: Date | null;
}
```

Located at `src/lib/api/services/accounting-service.ts`. Currently stores OAuth connections for QuickBooks and Sage — sync implementation is planned but not yet complete.

---

## Activity Timeline & Follow-Ups

### Activity Entity

Communication and event log for opportunities and clients:

```typescript
interface Activity {
  id: string;
  companyId: string;
  opportunityId: string | null;
  clientId: string | null;
  estimateId: string | null;
  invoiceId: string | null;

  type: ActivityType;  // note | email | call | meeting | estimate_sent | estimate_accepted |
                       // estimate_declined | invoice_sent | payment_received | stage_change |
                       // created | won | lost | system
  subject: string;
  content: string | null;
  outcome: string | null;
  direction: "inbound" | "outbound" | null;
  durationMinutes: number | null;

  createdBy: string | null;
  createdAt: Date;
}
```

### Follow-Up Entity

Scheduled reminders attached to opportunities or clients:

```typescript
interface FollowUp {
  id: string;
  companyId: string;
  opportunityId: string | null;
  clientId: string | null;

  type: FollowUpType;  // call | email | meeting | quote_follow_up | invoice_follow_up | custom
  title: string;
  description: string | null;
  dueAt: Date;
  reminderAt: Date | null;
  completedAt: Date | null;
  assignedTo: string | null;    // User ID
  status: FollowUpStatus;       // pending | completed | skipped
  completionNotes: string | null;
  isAutoGenerated: boolean;     // True if created by pipeline stage auto-follow-up rules
  triggerSource: string | null;

  createdBy: string | null;
  createdAt: Date;
}
```

Auto-generated follow-ups are triggered by stage transitions based on `autoFollowUpDays` in `PipelineStageConfig`.

### Follow-Up Helpers

```typescript
isFollowUpOverdue(followUp)   // true if Pending and past dueAt
isFollowUpToday(followUp)     // true if Pending and due today
```

---

## Supabase Schema Reference

### Tables (15 total)

| Table | Purpose |
|---|---|
| `opportunities` | Pipeline deals/leads |
| `stage_transitions` | Immutable stage change history |
| `pipeline_stage_configs` | Per-company stage configuration |
| `estimates` | Quotes/proposals |
| `invoices` | Billing documents |
| `line_items` | Line items for estimates and invoices (polymorphic) |
| `payment_milestones` | Progress billing milestones |
| `payments` | Payment records (insert-only, trigger-maintained) |
| `products` | Products/services catalog |
| `tax_rates` | Per-company tax rate configurations |
| `accounting_connections` | QuickBooks/Sage OAuth connections |
| `activities` | Communication and event log |
| `follow_ups` | Scheduled follow-up reminders |

### DB Conventions

- All tables use `snake_case` column names
- All monetary values: `NUMERIC(12,2)`
- Tax rates: stored as decimals (e.g. `0.0875` for 8.75%)
- `line_total` on line_items: `GENERATED ALWAYS AS (quantity * unit_price * (1 - discount_percent / 100.0)) STORED`
- `amount_paid`, `balance_due`, invoice `status` on invoices: maintained by payment triggers
- Soft deletes: `deleted_at TIMESTAMPTZ` (null = active)
- Payment voiding: `voided_at` + `voided_by` (NOT `deleted_at`)
- Row-Level Security (RLS) enabled on all tables

### RPC Functions

```sql
get_next_document_number(p_company_id UUID, p_document_type TEXT)
-- Returns sequential document number: "EST-0001", "INV-0001" etc.
-- Atomic, race-condition-safe

convert_estimate_to_invoice(p_estimate_id UUID, p_due_date TIMESTAMPTZ)
-- Atomically: validates estimate=approved, creates invoice, copies line items,
-- marks estimate as converted. Returns invoice UUID.
```

---

## Service Layer Patterns

### camelCase ↔ snake_case Conversion

All conversion happens at the service layer:
- DB rows come in as `snake_case` objects
- TypeScript interfaces use `camelCase`
- Each service has `mapEntityFromDb(row)` and `mapEntityToDb(data)` functions
- Never include `GENERATED ALWAYS` columns in writes

### Shared Helpers

```typescript
// src/lib/supabase/helpers.ts
requireSupabase(): SupabaseClient  // Throws if env vars not set
parseDate(val: unknown): Date | null
parseDateRequired(val: unknown): Date
```

### TanStack Query Integration

Hooks are in `src/lib/hooks/`:
- `useEstimates(companyId, options)` — `useQuery` wrapper
- `useInvoices(companyId, options)` — `useQuery` wrapper
- `useProducts(companyId)` — `useQuery` wrapper
- `useAccounting(companyId)` — `useQuery` wrapper
- Mutation hooks use optimistic updates for pipeline drag-and-drop

---

## Business Rules & Constraints

### Pipeline Rules

1. Every opportunity must have either `clientId` (Bubble client) or at least `contactName`
2. Stage transitions are always recorded as immutable `stage_transitions` rows
3. Moving to Won should set `actualCloseDate` and optionally `projectId`
4. Moving to Lost requires a `lostReason` (prompted in UI)
5. Win probability is per-stage by default but can be overridden per opportunity
6. Stale threshold: 7 days default (configurable per stage in `pipeline_stage_configs`)
7. Auto follow-ups generated based on `autoFollowUpDays` on stage config

### Estimate Rules

1. Estimates link to a Bubble `clientId` (required) and optionally an `opportunityId`
2. `estimateNumber` generated by RPC — never set manually
3. Editing only allowed in `Draft` or `ChangesRequested` status
4. Sending sets status → `Sent` + `sent_at = now`
5. `convertToInvoice` RPC is the only valid way to convert — validates estimate is `Approved`
6. Line items: `line_total` is DB-generated — never write this column
7. Optional line items: `isOptional=true, isSelected=true/false`; only selected items count in totals
8. Pricing stored as snapshots on estimate header, not recomputed from line items at runtime

### Invoice Rules

1. `invoiceNumber` generated by RPC — never set manually
2. `amount_paid`, `balance_due`, `status` maintained by DB triggers — never update manually
3. Payment voiding uses `voided_at`/`voided_by`, NOT `deleted_at`
4. Payment insert → trigger recalculates invoice balance and status
5. Payment void → trigger recalculates invoice balance and status
6. Invoices can link to an estimate, opportunity, and/or project
7. `voidInvoice` = sets status=Void; soft delete = sets deleted_at

### Product Rules

1. Products soft-deleted via `deleted_at`
2. Inactive products (`isActive=false`) excluded from catalog by default
3. Deleting a product does NOT cascade to line items (line items retain snapshot data)
4. `unitCost` is optional, used for margin calculation only

### Accounting Integration Rules

1. QuickBooks and Sage are the supported providers
2. OAuth tokens stored in `accounting_connections` — refresh token rotation handled server-side
3. Payment voiding uses `voided_at` not `deleted_at`

---

**Last Updated**: February 17, 2026
**Document Version**: 1.0
**Source**: ops-web git commits `0b268fd`, `2742b60`, `f5a01f1`, `81577c4`
