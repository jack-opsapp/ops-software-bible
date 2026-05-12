# 09_FINANCIAL_SYSTEM.md

**OPS Software Bible - Pipeline, Estimates, Invoices & Financial Architecture**

**Purpose**: Complete documentation of the OPS financial system — pipeline/CRM, estimates, invoices, payments, products catalog, and accounting integrations. All financial data lives in **Supabase** (PostgreSQL), separate from operational data in Bubble.io.

**Last Updated**: February 28, 2026
**Source Reference**: `C:\OPS\ops-web\src\lib\types\pipeline.ts`, `src\lib\api\services\`, iOS source at `OPS/OPS/`

---

## Table of Contents

1. [Dual-Database Architecture](#dual-database-architecture)
2. [Pipeline / CRM System](#pipeline--crm-system)
3. [Estimates System](#estimates-system)
4. [Invoices System](#invoices-system)
5. [Products & Services Catalog](#products--services-catalog)
6. [Payments](#payments)
7. [Expense Tracking System](#expense-tracking-system)
8. [Accounting Integrations](#accounting-integrations)
9. [Activity Timeline & Follow-Ups](#activity-timeline--follow-ups)
10. [Supabase Schema Reference](#supabase-schema-reference)
11. [Service Layer Patterns](#service-layer-patterns)
12. [Business Rules & Constraints](#business-rules--constraints)
13. [iOS Implementation](#ios-implementation)

---

## Dual-Database Architecture

OPS Web uses Supabase as its primary backend, with Bubble.io retained as legacy for some core entities during migration:

| Data Domain | Backend | Rationale |
|---|---|---|
| Projects, Tasks, Clients | Supabase (PostgreSQL) — iOS primary; Bubble legacy on web | Migrating to Supabase |
| Company, Users | Supabase (PostgreSQL) — iOS primary; Bubble legacy on web | Migrating to Supabase |
| Pipeline Opportunities | Supabase (PostgreSQL) | Relational, real-time, complex queries |
| Estimates, Invoices, Line Items | Supabase (PostgreSQL) | Financial data, needs DB triggers |
| Products Catalog | Supabase (PostgreSQL) | Per-company catalog |
| Payments | Supabase (PostgreSQL) | Insert-only, trigger-maintained balances |
| Accounting Connections | Supabase (PostgreSQL) | OAuth token storage |
| Expenses & Receipts | Supabase (PostgreSQL) | Expense tracking, OCR, batch approval |
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
  tags: string[];                      // e.g., ['email-import'] for Gmail-created leads

  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

**iOS parity (2026-05, BOOKS tab Phase 1):** The iOS `Opportunity` SwiftData model (`OPS/DataModels/Supabase/Opportunity.swift`) now models the full opportunity schema additively. All 47 columns are now read-side on iOS; AI/location/images fields (`aiSummary`, `aiStageConfidence`, `aiStageSignals`, `detectedValue`, `latitude`, `longitude`, lead image set) remain deferred to a later phase. Implementing commit: `9047b4b` in ops-ios.

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

**iOS parity (2026-05, BOOKS tab Phase 1):** iOS now writes `stage_transitions` rows on every stage move via the new `move_opportunity_stage` Postgres RPC. The RPC atomically updates `stage`, `stage_entered_at`, `stage_manually_set`, and INSERTs the transition row in a single transaction — eliminating the prior risk of a stage update landing without a paired transition record on partial network failure. RPC source: `ops-software-bible/migrations/2026-05-07-01-move-opportunity-stage-rpc.sql` (committed `b8db1aa`). iOS calling code: `OpportunityRepository.moveToStage(opportunityId:to:userId:)` (commit `bf26423`).

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

**iOS equivalence (2026-05, BOOKS tab Phase 1):** `OpportunityRepository` (`OPS/Network/Supabase/Repositories/OpportunityRepository.swift`, rebuilt in commit `bf26423`) mirrors the web service surface:

| iOS `OpportunityRepository` | Web `opportunity-service` | Notes |
|---|---|---|
| `fetchAll()` | `fetchOpportunities` | iOS pulls all non-deleted; client-side stage filtering |
| `fetchOne(_:)` | `fetchOpportunity` | iOS hydrates activities / follow-ups / transitions via separate fetchers below |
| `create(_:)` | `createOpportunity` | iOS sends explicit `title` when available; DB `trg_opportunities_default_title` still backfills empty titles |
| `update(_:fields:)` | `updateOpportunity` | Diff-PATCH (sparse field set) |
| `softDelete(_:)` | `deleteOpportunity` | Both implementations soft-delete via `deleted_at` |
| `moveToStage(opportunityId:to:userId:)` | `moveToStage` | iOS calls the `move_opportunity_stage` RPC; web still does updateOpportunity + records transition client-side |
| `markWon(opportunityId:actualValue:projectId:userId:)` | `markWon` | — |
| `markLost(opportunityId:reason:notes:userId:)` | `markLost` | — |
| `archive(_:)` / `unarchive(_:)` | — | **iOS-only.** No web equivalent yet — flag for future web parity. |
| `fetchActivities(opportunityId:)` | (included in `fetchOpportunity`) | iOS reads via direct Supabase query against `activities` |
| `fetchFollowUps(opportunityId:)` | (included in `fetchOpportunity`) | iOS reads via direct Supabase query against `follow_ups` |
| `fetchStageTransitions(opportunityId:)` | (included in `fetchOpportunity`) | iOS reads via direct Supabase query against `stage_transitions` |

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

The catalog supports two tiers of richness:

- **Barebones Products** — name + base_price + pricing_unit + tax. Behave like the original flat Product model. A "PICKET RAIL" Product at $2500 flat is one form-fill away (~8s in `ProductQuickAddSheet`).
- **Configurable Products** — carry options, pricing modifiers, and recipe rules. Used for cases like Canpro's "Custom Composite Railing" where a single Product expresses per-foot pricing, modifiers (Concrete +$5/ft), recipe templates (Color cascades through every BOM row), and quantity-scaling counts (Corners → corner hardware kits).

See `03_DATA_ARCHITECTURE.md` § 21 (Product) for the full SwiftData model with all 18 fields, and `07_SPECIALIZED_FEATURES.md` § 13a for resolver semantics and the worked Canpro example.

### Product Entity (post-Phase 13)

```typescript
type ProductPricingUnit =
  | 'each' | 'flat_rate' | 'linear_foot' | 'sqft' | 'hour' | 'day';

// On the wire: 'service' | 'material' | 'package'. The Swift enum case
// names `.good` and `.package` map to the wire values `material` and
// `package` respectively (`.good` is legacy — kept for source stability).
type ProductKind = 'service' | 'material' | 'package';

type LineItemType = 'LABOR' | 'MATERIAL' | 'OTHER';

// User-facing iOS taxonomy (added 2026-05-10, bug 164e0595). Derives
// kind + type on save. See § Catalog UI below for the mapping table.
type ProductCategory = 'service' | 'material' | 'fee' | 'bundle';

interface Product {
  id: string;
  companyId: string;
  name: string;
  description: string | null;

  type: LineItemType;
  kind: ProductKind;

  basePrice: number;              // primary unit price (replaces default_price)
  unitCost: number | null;        // for margin tracking
  pricingUnit: ProductPricingUnit;

  unit: string | null;            // legacy free-text unit (kept for back-compat)
  category: string | null;        // legacy free-text category (separate from catalog_categories)
  sku: string | null;

  taxable: boolean;
  isActive: boolean;
  isFavorite: boolean;

  minimumCharge: number | null;
  minimumQuantity: number | null;
  showBomOnEstimate: boolean;
  showInStorefront: boolean;
  tieredPricing: jsonb | null;    // power-user passthrough

  taskTypeId: string | null;
  taskTypeRef: string | null;
  unitId: string | null;                // FK catalog_units.id
  linkedCatalogItemId: string | null;   // FK catalog_items.id (added 2026-05-10, bug 164e0595)

  createdAt: Date | null;
  updatedAt: Date | null;
  deletedAt: Date | null;
}
```

**Wire-field fix**: earlier builds wrote `unit_price`/`cost_price` — columns that do not exist in Supabase. The DTO now correctly maps `base_price`/`unit_cost`. The legacy `default_price` column is preserved with a Postgres trigger mirroring `base_price` ↔ `default_price` (see `migrations/2026-05-06-02-catalog-views-triggers.sql`) until ops-web cuts over to `base_price`.

### iOS Catalog UI — New Product Sheet (post bug 164e0595)

The legacy iOS New Product sheet forced two overlapping pickers (`Kind` Service/Good + `Line item type` Labor/Material/Other). The 2026-05-10 redesign collapses these into a single 4-way `ProductCategory` picker. The form derives `kind` + `type` on save so old App Store builds and the web app keep reading sensible values without any client-side change.

| User picks | wire `kind` | wire `type` | Default `taxable` | Task type | Components | Stock link |
|---|---|---|---|---|---|---|
| Service  | `service`  | `LABOR`    | `true`  | required | optional | — |
| Material | `material` | `MATERIAL` | `true`  | — | — | optional |
| Fee      | `service`  | `OTHER`    | `false` | — | — | — |
| Bundle   | `package`  | `OTHER`    | `true`  | required | optional | — |

Per-category form affordances:
- **Service / Bundle**: required `Task Type` picker writes `task_type_ref`. Optional `// COMPONENTS` disclosure stages recipe rows (variant-pinned only) via `AddProductMaterialSheet` in draft mode; rows commit to `product_materials` after Product create.
- **Material**: optional `// SHOW IN STOCK` toggle. When ON, the operator either picks an existing `catalog_items` row or creates one (plus a default `catalog_variants` row) via `CatalogRepository.createDefaultItemForProduct`. The chosen id is written to `linked_catalog_item_id`.
- **Fee**: no extras — minimises the form so a permit / passthrough entry stays an 8-second flow.

The `Taxable` toggle pre-defaults per category (Service/Material/Bundle → ON, Fee → OFF). Once the operator flips it manually, the override sticks across category switches (`taxableUserOverridden` flag in the form's view-state).

**Inventory deduction on sale is not yet wired** — see § P1-28 scope for `inventory_deductions` integration. The `linked_catalog_item_id` column is present so that work can land without further iOS changes.

Products are soft-deleted. `ProductService.fetchProducts(companyId, activeOnly=true)` returns only active, non-deleted products by default. Line items reference a product via `productId`. When a product is added to an estimate, it pre-fills the line item name, description, `resolved_unit_price`, unit cost, unit, taxable flag, type, and `taskTypeId`.

### Line Item Snapshot (NEW post-Phase 13)

`line_items` gained three columns to capture per-line configuration at the moment of creation. Estimates and invoices are signed contracts — once a line is written, later edits to the Product must not retroactively change the historical estimate.

```sql
ALTER TABLE line_items
  ADD COLUMN configured_options       jsonb        NULL,
  ADD COLUMN resolved_unit_price      numeric      NULL,
  ADD COLUMN resolved_options_label   text         NULL;
```

| Column | Purpose |
|---|---|
| `configured_options` | Per-line jsonb of `{option_id: option_value_id_or_int_or_bool}`. Captured at line creation. Read by `RecipeResolver` at install task creation to materialize the cut list. |
| `resolved_unit_price` | Snapshot of `base_price + applicable modifiers`. Frozen at line creation; never re-resolves. |
| `resolved_options_label` | Printed-estimate-friendly summary ("TM · Black · Concrete · 4 corners"). |

**Pricing freeze**: pricing modifiers are evaluated and folded into `resolved_unit_price` at line-item creation. Modifying the Product after the estimate is sent does not change the estimate's totals.

**Recipe lazy-resolution**: recipes do **not** resolve at estimate creation. They resolve at install task creation by reading `configured_options` and walking `product_materials`. This is intentional — the cut list must reflect the configuration the customer signed, not whatever the Product looks like today.

### Recipe Semantics

`product_materials` rows are either:

- **Variant-pinned** — `catalog_variant_id` non-null, `catalog_item_id` null. The recipe always pulls this exact SKU regardless of options.
- **Family-pinned with selector** — `catalog_item_id` non-null, `catalog_variant_id` null, `variant_selector` jsonb populated. The selector references option keys (`{"color":"$option.color","mount":"$option.mount_type"}`) — at resolution time, the resolver walks the line's `configured_options`, matches values, and finds the variant on that family with those option-value combos.

CHECK constraint `(catalog_variant_id IS NOT NULL) <> (catalog_item_id IS NOT NULL)` enforces mutual exclusion.

`scaled_by_option_id` lets a recipe row scale by an integer-kind option's value. Example: a "Corner Hardware Kit" row with `scaled_by_option_id = corners_count` and `quantity_per_unit = 1` yields 4 kits when the line specifies 4 corners.

### Resolution Timing

| Event | What runs | Output |
|---|---|---|
| Line item created (manually or via adapter) | `ProductConfigurationResolver` | `configured_options`, `resolved_unit_price`, `resolved_options_label` |
| Estimate sent / approved | (no-op for catalog) | — |
| Project transitions to `.inProgress` and install tasks generated | `CutListMaterializer` per task → `RecipeResolver` per line | `task_materials` rows pinned to specific `catalog_variants` |
| Cut-list materialization is idempotent | re-running replaces the existing rows | — |

---

## Expense Tracking System

### Overview

Full expense submission, receipt OCR scanning, batch approval workflow, and accounting sync system. All roles can submit expenses; office/admin approve field crew submissions. Expenses live in the Pipeline tab under a dedicated "EXPENSES" segment.

### Expense Lifecycle

```
draft → submitted → approved → reimbursed
                  ↘ rejected
```

- **Draft**: Created by user, not yet submitted for review
- **Submitted**: Sent for approval (auto-approve if under threshold)
- **Approved**: Approved by office/admin, triggers accounting sync if connected
- **Rejected**: Rejected with reason, can be edited and resubmitted
- **Reimbursed**: Payment confirmed (terminal state)

### Threshold-Based Approval

Company-configurable via `expense_settings`:

1. **Auto-approve threshold**: Expenses under this amount auto-approve on submission
2. **Admin approval threshold**: Expenses above this amount require admin (not just office crew)
3. Expenses between the two thresholds require office crew or admin approval

### Batch Review Workflow

**Always-bundle on submit (post-2026-05-08).** Every submitted expense is attached to an open batch (`expense_batches.status = 'pending_review'`) at the moment of submission. The `review_frequency` setting controls how the open batch is *scoped*:

| Frequency | Batch scope | Period window |
|---|---|---|
| `per_job` | One batch per `(submitted_by, scope_project_id)` — multi-allocation forbidden in the form for these companies | Single-day (`expense_date` to `expense_date`) |
| `weekly` | One batch per `(submitted_by, week)` | Mon–Sun containing `expense_date` |
| `biweekly` | One batch per `(submitted_by, half-month)` | 1–14 or 15–end-of-month containing `expense_date` |
| `monthly` | One batch per `(submitted_by, month)` | First-to-last day of the month containing `expense_date` |
| `quarterly` | One batch per `(submitted_by, quarter)` | First-to-last day of the quarter containing `expense_date` |

Subsequent expenses by the same user falling into the same scope accumulate into the same open batch until an admin acts on it (approve / send back / reject). At that point the batch is closed and a new submission opens a fresh one.

**Atomic get-or-create.** iOS submits via the `public.get_or_create_open_batch(p_company_id, p_submitted_by, p_period_start, p_period_end, p_scope_project_id)` RPC. A partial unique index on `(company_id, submitted_by, period_start, period_end, scope_project_id) WHERE status='pending_review' AND amendment_number=0` (NULLS NOT DISTINCT) makes concurrent submissions safe.

**Per-expense auto-approve preserved.** If `amount < expense_settings.auto_approve_threshold`, the expense bypasses the batch entirely: `draft → approved` directly with `approvedBy = 'auto'` and immediate `accounting-sync-expense` call. No notification, no batch, matching the pre-existing semantics.

**Notification dispatch.** On above-threshold submission, recipients are looked up via `public.users_with_permission(company_id, 'expenses.approve')` — never by `users.role`. Sites that previously filtered by role (`AppState.swift`, `ExpenseViewModel.swift`, `TimeOffRequestSheet.swift`, `QuantityAdjustmentSheet.swift`) now use this permission-gated lookup, honoring custom roles and per-user overrides.

**Orphan recovery.** Pre-fix client versions can leave expenses in `submitted` status with `batch_id = NULL`. `ExpensesListView` shows an orphan-recovery banner whenever any exist for the company; tapping `BUNDLE` re-runs always-bundle for each orphan, attaching it to the appropriate open batch (one notification per resulting batch, not per expense).

**`accounting-batch-create` Edge Function** *(deprecated 2026-05-08)* — the cron-driven lazy batcher is no longer the source of truth. The function had a latent bug in production (references to nonexistent column `expense_count` and table `accounting_sync_log` made every invocation fail silently — verified zero batches with `status='pending'` ever existed). With always-bundle, lazy batching is unnecessary. The function should be removed via the Supabase dashboard.

### Receipt OCR (Apple Vision)

On-device OCR using Apple's Vision framework (`VNRecognizeTextRequest` with `.accurate` recognition level). No external vendor dependency.

**Extracted fields**: merchant name, date, total, subtotal, tax amount, payment method (cash/card detection), raw text.

**Architecture**: Protocol-based (`ExpenseOCRServiceProtocol`) for future swappability (e.g., Veryfi integration).

### Multi-Project Expense Splitting

Expenses can be attributed to zero or more projects via `expense_project_allocations`:
- Each allocation has an `expense_id`, `project_id`, and `percentage` (0-100)
- Percentages must sum to 100% if any allocations exist (validated client-side in `ExpenseFormSheet.validate`)
- Project assignment is optional (company-configurable via `require_project_assignment`)
- **`per_job` companies allow exactly one allocation per expense** — the form blocks the "ADD PROJECT" button after the first project is selected, since per-job batches are project-scoped

### Currency Handling

`expenses.currency` (text, default `'USD'`) stores the ISO 4217 code. The form's currency picker defaults from `Locale.current.currency?.identifier` (locale-aware) and is overridable per-expense. Canadian crews logging CAD receipts in a USD-default world were silently mis-recording before 2026-05-08 — this fix surfaces currency in the form and persists it through `CreateExpenseDTO`/`UpdateExpenseDTO`.

### Supabase Tables (6)

| Table | Purpose |
|---|---|
| `expenses` | Core expense records (amount, merchant, status, receipt URL, OCR data, **currency**) |
| `expense_project_allocations` | Many-to-many linking expenses to projects with percentage split |
| `expense_categories` | Company-configurable categories with icons (9 defaults seeded) |
| `expense_settings` | Per-company settings (review frequency, thresholds, policy toggles) |
| `expense_batches` | Groups of expenses for batch review by office/admin. **`scope_project_id` (nullable uuid)** identifies per-job batches; NULL for period batches |
| `accounting_category_mappings` | Maps OPS categories to external chart of accounts (QB/Sage) |

### Supabase Functions (expense-related)

| Function | Purpose |
|---|---|
| `public.users_with_permission(p_company_id, p_permission, p_required_scope)` | Returns user IDs in a company holding a permission. Honors role grants, per-user overrides, and the `is_company_admin`/`account_holder_id`/`admin_ids` escape hatches. **Use for all recipient lookups — never filter by `users.role`.** |
| `public.get_or_create_open_batch(p_company_id, p_submitted_by, p_period_start, p_period_end, p_scope_project_id)` | Always-bundle helper — returns the user's open batch matching the scope or creates one atomically (race-safe via partial unique index + on-conflict re-select). |
| `public.recalculate_expense_batch_total(p_batch_id)` | Recomputes and persists `expense_batches.total_amount` from non-deleted attached expenses. Called after attaching expenses on submission. |
| `public.has_permission(p_user_id, p_permission, p_required_scope)` | Single-user permission check. Note: does NOT currently apply `user_permission_overrides` — only `user_roles → role_permissions` plus the admin escape hatches. iOS `PermissionService.fetchPermissions` applies overrides client-side. (Latent inconsistency — flagged for follow-up.) |
| `public.get_next_expense_batch_number(p_company_id)` | Returns next sequential batch number, format `EXP-BATCH-NNNN`. |

### Default Expense Categories (9)

Seeded on first load via `ExpenseRepository.seedDefaultCategories()`:

| Category | Icon |
|---|---|
| Materials & Supplies | shippingbox.fill |
| Equipment Rental | wrench.and.screwdriver.fill |
| Fuel & Mileage | fuelpump.fill |
| Subcontractor | person.2.fill |
| Permits & Fees | doc.text.fill |
| Tools | hammer.fill |
| Safety Equipment | shield.checkered |
| Office Supplies | paperclip |
| Other | ellipsis.circle |

### Entry Points

1. **Pipeline tab → Expenses → + FAB** — General submission, no project pre-selected
2. **Project Details → Expenses section** — Pre-fills project allocation
3. **Project Action Bar → Receipt button** — Opens camera, pre-fills project on capture

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

Located at `src/lib/api/services/accounting-service.ts`. Stores OAuth connections for QuickBooks and Sage. Full sync implemented via Supabase Edge Functions.

### Edge Functions (3)

All deployed to Supabase, invoked via `SUPABASE_URL/functions/v1/<function-name>`. All use `verify_jwt: false` with manual auth header validation internally.

#### `accounting-oauth`

Handles OAuth flows for QuickBooks and Sage.

**Actions** (via `action` field in JSON body):
- `authorize` — Returns OAuth redirect URL for the provider
- `callback` — Exchanges authorization code for tokens, upserts `accounting_connections`
- `refresh` — Refreshes expired access token using refresh token
- `disconnect` — Clears tokens, sets `is_connected = false`

**Token management**:
- QuickBooks: Access tokens expire every 60 minutes, refresh tokens every 100 days
- Sage: Access tokens expire every 60 minutes
- Token refresh called automatically by `accounting-sync-expense` before sync operations

**Required env vars**: `QB_CLIENT_ID`, `QB_CLIENT_SECRET`, `QB_REDIRECT_URI`, `SAGE_CLIENT_ID`, `SAGE_CLIENT_SECRET`, `SAGE_REDIRECT_URI`

#### `accounting-sync-expense`

Syncs an approved expense to the company's connected accounting system.

**Trigger**: Called from iOS via `client.functions.invoke("accounting-sync-expense")` in `ExpenseRepository.triggerAccountingSync()`. Fires automatically from two paths in `ExpenseViewModel`:
- `approveExpense()` — after office/admin manually approves an expense
- `submitExpense()` — after auto-approve (expense amount < `expense_settings.auto_approve_threshold`)

Both paths are fire-and-forget (`Task { await ... }`), so the approval UX is never blocked by accounting sync.

**Flow**:
1. Fetch `accounting_connections` for the company
2. If no active connection → exit silently (no side effects for non-integrated companies)
3. Refresh token if expired (calls `accounting-oauth` refresh endpoint)
4. Map expense fields to provider format using `accounting_category_mappings`
5. POST to provider API
6. Update `accounting_sync_status` and `accounting_sync_id` on expense
7. Log to `accounting_sync_log`

**QuickBooks mapping**: OPS expense → QBO `Purchase` object
- `merchant_name` → `EntityRef` (vendor lookup/create)
- `amount` → `TotalAmt`
- `expense_date` → `TxnDate`
- Category → `AccountRef` via `accounting_category_mappings`
- Project allocation → `CustomerRef` for job costing

**Sage mapping**: OPS expense → Sage `OtherPayment` object
- `merchant_name` → `ContactId` (contact lookup/create)
- Category → `LedgerAccountId` via `accounting_category_mappings`

**Retry logic**: On transient failures (429, 5xx), retry up to 3 times with exponential backoff.

#### `accounting-batch-create`

Cron-triggered function that creates expense batches. Runs daily at 00:00 UTC.

**Flow**:
1. Query all companies with `expense_settings`
2. For each company, check if a batch is due based on `review_frequency`
3. Collect `submitted` expenses not yet in a batch
4. Create `expense_batch`, assign `batch_id` on expenses, calculate total
5. Log to `accounting_sync_log`

**Optional env var**: `CRON_SECRET` — shared secret for cron invocations via `X-Cron-Secret` header.

### accounting_category_mappings

When a company connects QB or Sage, they map each OPS expense category to an external chart of accounts entry. The mapping is stored in `accounting_category_mappings` and used on every sync to route expenses to the correct account.

| Column | Purpose |
|---|---|
| `company_id` | Company owning the mapping |
| `expense_category_id` | OPS expense category ID |
| `provider` | "quickbooks" or "sage" |
| `external_account_id` | Account ID in external system |
| `external_account_name` | Human-readable account name |

If no mapping exists for a category, the sync uses a fallback "Uncategorized Expenses" account.

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

### Tables (22 total)

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
| `accounting_sync_log` | Sync event log (success/error tracking) |
| `accounting_category_mappings` | OPS category → external chart of accounts mapping |
| `expenses` | Core expense records with receipt images and OCR data |
| `expense_project_allocations` | Multi-project expense attribution with percentage split |
| `expense_categories` | Company-configurable expense categories with icons |
| `expense_settings` | Per-company expense policy (thresholds, frequency, toggles) |
| `expense_batches` | Grouped expenses for batch review by office/admin |
| `activities` | Communication and event log |
| `follow_ups` | Scheduled follow-up reminders |
| `project_notes` | Project-level notes with @mentions and attachments (Feb 2026) |

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

get_next_expense_batch_number(p_company_id UUID)
-- Returns next sequential batch number for the company.
-- Counts existing batches + 1. Used by accounting-batch-create Edge Function.
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

### Expense Rules

1. All roles can create and submit expenses (requires `expenses.create` permission — all preset roles have it)
2. Only users with `expenses.approve` permission can approve/reject expenses (Admin, Owner, Office by default). Enforced at app layer + Supabase RLS (migration 016)
3. Auto-approve logic: if amount < `auto_approve_threshold`, status goes directly to `approved` on submission
4. Expenses above `admin_approval_threshold` require admin approval specifically (user must have `expenses.approve` permission)
5. `batch_id` is null until the expense is collected into a batch by the cron Edge Function
6. `accounting_sync_status`: `pending` (no connection), `synced` (pushed to QB/Sage), `error` (sync failed)
7. Receipt images uploaded to S3 via `S3UploadService.shared.uploadExpenseReceipt()` — full-size (max 2048px) at `company-{companyId}/expenses/receipt_{expenseId}_{timestamp}.jpg` plus 512px thumbnail variant
8. OCR data (raw text, extracted fields, confidence) stored in `ocr_raw_data` (JSONB) and `ocr_confidence` (0-1) for audit trail — captured from `AppleVisionOCRService` via `OCRResult.rawDataDict`
9. Expense allocations (project splits) use delete-and-reinsert pattern when updated
10. Default categories seeded automatically on first load per company

### Accounting Integration Rules

1. QuickBooks and Sage are the supported providers
2. OAuth tokens stored in `accounting_connections` — refresh token rotation handled server-side via `accounting-oauth` Edge Function
3. Approved expenses auto-sync to connected accounting when `sync_enabled = true`
4. Category mapping via `accounting_category_mappings` — each OPS category maps to an external account
5. Vendor/contact lookup-or-create pattern used for `merchant_name` in both QB and Sage
6. Sync retries up to 3x with exponential backoff on transient failures (429, 5xx)
7. All sync operations logged in `accounting_sync_log` for audit trail
8. Payment voiding uses `voided_at` not `deleted_at`

---

## iOS Implementation

The full Pipeline, Estimates, Invoices, and Accounting system is implemented natively on iOS using SwiftUI, with Supabase as the backend via dedicated Repository classes and DTOs.

### iOS View Layer

**Location**: `OPS/OPS/Views/Estimates/`, `OPS/OPS/Views/Invoices/`, `OPS/OPS/Views/Accounting/`

#### Estimates Views (6 files)

| File | Purpose |
|---|---|
| `EstimatesListView.swift` | List of all company estimates with search, filter chips (ALL/DRAFT/SENT/APPROVED), pull-to-refresh, and a FAB for creating new estimates. Swipe-right on draft to send, swipe-right on approved to convert to invoice. |
| `EstimateDetailView.swift` | Full detail for a single estimate showing header (estimate number, title, total, status badge, age), line items section, totals section (subtotal/tax/total), and a context-dependent sticky footer (EDIT/SEND for draft, RESEND/MARK APPROVED for sent, CONVERT TO INVOICE for approved). Overflow menu provides additional actions. |
| `EstimateFormSheet.swift` | Create or edit an estimate with collapsible sections (Client & Project, Line Items, Payment & Terms, Notes & Attachments). Line items always expanded. Sticky footer shows running subtotal/tax/total and a SEND EST button. Auto-creates estimate on first open in create mode. |
| `EstimateCard.swift` | Card component for estimate list showing estimate number, title, total, status badge with color, and age. Supports swipe-right (SEND for draft, CONVERT for approved) and swipe-left (VOID). |
| `LineItemEditSheet.swift` | Bottom sheet for creating or editing a line item. Fields: description, type picker (LABOR/MATERIAL/OTHER), quantity, unit, unit price, optional toggle, taxable toggle. Shows computed line total. Delete button in edit mode. |
| `ProductPickerSheet.swift` | Bottom sheet to select a product from the catalog. Search field filters products by name. Tapping a product adds it as a line item (pre-fills name, type, default price, productId). Loads products via `ProductRepository.fetchAll()`. |

#### Invoice Views (4 files)

| File | Purpose |
|---|---|
| `InvoicesListView.swift` | List of all invoices with filter chips (ALL/UNPAID/OVERDUE/PAID), search, pull-to-refresh. Swipe-right to record payment, swipe-left to void. No FAB (invoices are created via estimate conversion). |
| `InvoiceDetailView.swift` | Full detail for a single invoice showing header (invoice number, title, total, status badge, due/overdue date), line items section, totals section (subtotal/tax/total/paid/balance due), payments section. Sticky footer is context-dependent: SEND INVOICE for draft, BALANCE DUE + RECORD PAYMENT for unpaid, PAID IN FULL for paid, VOIDED for void. Toolbar menu provides Send/Record Payment/Void actions. |
| `InvoiceCard.swift` | Card component showing invoice number, title, total, status badge with color, and due/overdue date. Overdue invoices get a red border. Swipe-right reveals PAYMENT action, swipe-left reveals VOID. |
| `PaymentRecordSheet.swift` | Bottom sheet to record a payment. Shows invoice context (number + balance). Fields: amount (pre-filled with balance due), payment method picker (all `PaymentMethod` cases with checkmark selection), optional notes. Calls `InvoiceViewModel.recordPayment()`. |

#### Expense Views (7 files)

**Location**: `OPS/OPS/Views/Expenses/`

| File | Purpose |
|---|---|
| `ExpensesListView.swift` | List of all company expenses with search, filter chips (ALL/PENDING/APPROVED/REJECTED), pull-to-refresh, and FAB for creating new. Swipe-right on draft to submit, swipe-left to delete. |
| `ExpenseDetailView.swift` | Full detail for a single expense: receipt image (tappable for full-screen), OCR-extracted fields, project allocations with percentages, approval status/history. Context-dependent action footer (EDIT/SUBMIT for draft, APPROVE/REJECT for office/admin). |
| `ExpenseFormSheet.swift` | Create/edit sheet with camera capture button, OCR auto-fill, detail fields (merchant, amount, tax, date, category, payment method), project allocation section with percentage sliders, notes. Accepts optional `prefilledProjectId`. Sticky footer with submit. |
| `ExpenseCard.swift` | Card for list: merchant name + amount, category icon + name, date, status badge. Swipe-right = SUBMIT (drafts), swipe-left = DELETE. |
| `ExpenseBatchReviewView.swift` | Office/admin batch review. Header with batch info (period, count, total). Expandable expense cards with receipt thumbnail + details. Approve/reject per item. "Approve All" toolbar button. |
| `ExpenseCategorySettingsView.swift` | Category management: icon + name list, active toggle, add custom category sheet. |
| `ExpenseSettingsView.swift` | Company expense settings: review frequency picker, threshold amount fields, policy toggles (require receipt, require project), save button. |

#### A/R Views (1 file)

| File | Purpose |
|---|---|
| `ARAgingDetailView.swift` | Read-only A/R drill-down. Two sections: (1) **Aging Buckets** horizontal bar chart (0–30d, 31–60d, 61–90d, 90d+) using Swift Charts, (2) **Top Outstanding** list of top 5 clients by outstanding balance. Loaded via `AccountingRepository.fetchAllInvoices()`. Presented as a sheet from the BOOKS carousel's A/R card top-chase tile and from the carousel's OUTSTANDING tile. Pull-to-refresh. (Note: `AccountingDashboard.swift` was replaced by this view in an earlier session — bible drift D1 caught and reconciled 2026-05-11 during Books Phase 2 work.) |

### iOS ViewModels

**Location**: `OPS/OPS/ViewModels/`

All ViewModels are `@MainActor` `ObservableObject` classes. Each exposes `@Published` state, sets up a repository via `setup(companyId:)`, and provides async methods for data operations.

#### PipelineViewModel

Manages the pipeline CRM opportunity list.

- **Published state**: `opportunities`, `selectedStage` (filter, nil = ALL), `searchText`, `isLoading`, `error`
- **Computed properties**: `filteredOpportunities` (by stage + search on contactName/jobDescription/source), `totalPipelineValue`, `weightedPipelineValue`, `activeDealsCount`, `stagesWithCounts`
- **Operations**: `loadOpportunities()`, `advanceStage(opportunity:)` (optimistic update), `markLost(opportunity:reason:)`, `markWon(opportunity:)`, `createOpportunity(...)`, `updateOpportunity(...)`, `deleteOpportunity(...)`
- **Repository**: `OpportunityRepository`

#### EstimateViewModel

Manages the estimate list, line items, filtering, and status actions.

- **Published state**: `estimates`, `selectedFilter` (ALL/DRAFT/SENT/APPROVED enum), `searchText`, `isLoading`, `error`
- **Internal state**: `lineItemDTOs` dictionary keyed by estimate ID
- **Computed**: `filteredEstimates` (by filter + search on title/estimateNumber)
- **Operations**: `loadEstimates()`, `lineItems(for:)`, `createEstimate(title:companyId:opportunityId?:clientId?:)`, `addLineItem(estimateId:description:type:quantity:unitPrice:isOptional:productId?:)`, `updateLineItem(id:estimateId:description?:quantity?:unitPrice?:isOptional?:)`, `deleteLineItem(id:estimateId:)`, `updateTitle(estimateId:title:)`, `sendEstimate(_:)`, `markApproved(_:)`, `convertToInvoice(_:)`
- **Repository**: `EstimateRepository`

#### InvoiceViewModel

Manages the invoice list, line items, payments, filtering, and status actions.

- **Published state**: `invoices`, `selectedFilter` (ALL/UNPAID/OVERDUE/PAID enum), `searchText`, `isLoading`, `error`
- **Internal state**: `lineItemDTOs` and `paymentDTOs` dictionaries keyed by invoice ID
- **Computed**: `filteredInvoices` (by filter + search on title/invoiceNumber)
- **Operations**: `loadInvoices()`, `lineItems(for:)`, `payments(for:)`, `recordPayment(invoiceId:companyId:amount:method:notes?:)`, `voidInvoice(_:)`, `sendInvoice(_:)`
- **Critical pattern**: After `recordPayment`, the ViewModel re-fetches the invoice from Supabase to get DB-trigger-updated `amountPaid`, `balanceDue`, and `status`. Never manually updates these fields.
- **Repository**: `InvoiceRepository`

#### ExpenseViewModel

Manages expense list, categories, batches, OCR scanning, and approval actions.

- **Published state**: `expenses`, `categories`, `batches`, `selectedFilter` (ALL/PENDING/APPROVED/REJECTED enum), `searchText`, `isLoading`, `error`, `settings`
- **Computed**: `filteredExpenses` (by filter + search on merchantName/description)
- **Operations**: `loadAll()` (parallel: expenses + categories + settings + batches), `loadExpenses()`, `createExpense(...)`, `updateExpense(...)`, `deleteExpense(_:)`, `submitExpense(_:)` (with auto-approve threshold check), `approveExpense(_:)`, `rejectExpense(_:reason:)`, `setAllocations(_:allocations:)`, `loadCategories()`, `loadBatches()`, `toggleCategory(_:isActive:)`, `scanReceipt(image:)` (OCR via AppleVisionOCRService), `loadSettings()`, `saveSettings(_:)`, `createCategory(companyId:name:icon:)`
- **Project-scoped**: `loadExpensesForProject(projectId:)` — loads expenses allocated to a specific project
- **Repository**: `ExpenseRepository`

#### OpportunityDetailViewModel

Manages activities and follow-ups for a single opportunity detail screen.

- **Published state**: `activities`, `followUps`, `isLoading`, `error`
- **Operations**: `loadDetails(for:)` (parallel fetch of activities + follow-ups via `async let`), `logActivity(opportunityId:companyId:type:body?:)`, `createFollowUp(opportunityId:companyId:type:dueAt:notes?:)`
- **Repository**: `OpportunityRepository`

### iOS Supabase Repositories

**Location**: `OPS/OPS/Network/Supabase/Repositories/`

All repositories take `companyId` in their initializer and use `SupabaseService.shared.client` for the Supabase connection.

#### EstimateRepository

- `fetchAll()` -- selects `*, line_items(*)` filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(estimateId)` -- selects `*, line_items(*)` for single estimate
- `create(CreateEstimateDTO)` -- inserts estimate, returns with line items
- `updateTitle(estimateId, title)` -- updates title field only
- `updateStatus(estimateId, status)` -- updates status, returns full estimate with line items
- `addLineItem(CreateLineItemDTO)` -- inserts into `line_items` table
- `updateLineItem(id, UpdateLineItemDTO)` -- updates line item fields
- `deleteLineItem(id)` -- hard deletes from `line_items` table
- `convertToInvoice(estimateId)` -- calls Supabase RPC `convert_estimate_to_invoice`, returns `InvoiceDTO`

#### InvoiceRepository

- `fetchAll()` -- selects `*, invoice_line_items(*), payments(*)` filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(invoiceId)` -- selects `*, invoice_line_items(*), payments(*)` for single invoice
- `recordPayment(CreatePaymentDTO)` -- inserts into `payments` table (DB trigger maintains invoice balance/status)
- `updateStatus(invoiceId, status)` -- updates status field
- `voidInvoice(invoiceId)` -- sets status to void (calls `updateStatus` internally)

#### AccountingRepository

- `fetchAllInvoices()` -- selects `*, invoice_line_items(*), payments(*)` filtered by `company_id`, ordered by `created_at` desc. Used exclusively by `AccountingDashboard` for read-only financial health computations (AR aging, status counts, top outstanding).

#### ExpenseRepository

- `fetchAll()` -- selects `*, expense_project_allocations(*), expense_categories(*)` filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(expenseId)` -- single expense with allocations and category
- `create(CreateExpenseDTO)` -- inserts expense
- `update(expenseId, UpdateExpenseDTO)` -- updates draft expense fields
- `updateStatus(expenseId, status)` -- updates status field
- `approve(expenseId, approvedBy)` -- sets status=approved, approved_by, approved_at
- `reject(expenseId, rejectedBy, reason)` -- sets status=rejected, rejection_reason
- `softDelete(expenseId)` -- sets `deleted_at` timestamp
- `setAllocations(expenseId, [CreateExpenseAllocationDTO])` -- delete existing + insert new (transactional)
- `fetchByProject(projectId)` -- expenses allocated to a project (via allocation join)
- `fetchCategories()` -- active categories for the company
- `createCategory(CreateExpenseCategoryDTO)` -- add custom category
- `updateCategory(id, name, icon, isActive)` -- modify category
- `seedDefaultCategories()` -- seeds 9 default categories if none exist for company
- `fetchBatches()` -- all batches for the company
- `fetchBatchExpenses(batchId)` -- expenses in a specific batch
- `fetchSettings()` -- company expense settings
- `upsertSettings(ExpenseSettingsDTO)` -- save/update settings
- `triggerAccountingSync(expenseId)` -- fire-and-forget call to `accounting-sync-expense` Edge Function via `client.functions.invoke()`; logs errors but does not throw
- `fetchCategoryMappings(provider)` -- accounting category mappings for a provider (quickbooks/sage)
- `upsertCategoryMapping(CreateAccountingCategoryMappingDTO)` -- upsert mapping (unique on company_id + category_id + provider)
- `deleteCategoryMapping(id)` -- remove a mapping

#### OpportunityRepository

- `fetchAll()` -- selects all opportunities filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(opportunityId)` -- single opportunity
- `fetchActivities(for opportunityId)` -- selects activities for an opportunity, ordered by `created_at` desc
- `fetchFollowUps(for opportunityId)` -- selects follow-ups for an opportunity, ordered by `due_at` asc
- `create(CreateOpportunityDTO)` -- inserts new opportunity
- `logActivity(CreateActivityDTO)` -- inserts into `activities` table
- `createFollowUp(CreateFollowUpDTO)` -- inserts into `follow_ups` table
- `advanceStage(opportunityId, to stage, lossReason?)` -- updates `stage` (and optionally `loss_reason`) on the opportunity
- `update(opportunityId, UpdateOpportunityDTO)` -- updates opportunity fields
- `delete(opportunityId)` -- hard deletes opportunity

#### ProductRepository

- `fetchAll()` -- selects active products (`is_active = true`) filtered by `company_id`, ordered by `name` asc
- `create(CreateProductDTO)` -- inserts new product
- `update(id, UpdateProductDTO)` -- updates product fields
- `deactivate(id)` -- sets `is_active` to false (soft deactivation)

### iOS Financial DTOs

**Location**: `OPS/OPS/Network/Supabase/DTOs/`

7 DTO files cover the financial system. All use `Codable` with `CodingKeys` for `snake_case` <-> `camelCase` mapping. Each read-DTO has a `toModel()` method to convert to the local domain model.

#### ExpenseDTOs.swift

| DTO | Purpose |
|---|---|
| `ExpenseDTO` | Read DTO for expenses table. Fields: id, companyId, submittedBy, status, categoryId, merchantName, description, amount, taxAmount, currency, expenseDate, paymentMethod, receiptImageUrl, receiptThumbnailUrl, ocrRawData, ocrConfidence, batchId, approvedBy, approvedAt, rejectedBy, rejectionReason, accountingSyncStatus, accountingSyncId, deletedAt, createdAt, updatedAt. Nested: `allocations: [ExpenseAllocationDTO]?`, `category: ExpenseCategoryDTO?`. |
| `CreateExpenseDTO` | Write DTO. Fields: companyId, submittedBy, categoryId, merchantName, description, amount, taxAmount, expenseDate, paymentMethod, receiptImageUrl. |
| `UpdateExpenseDTO` | Partial update DTO. Optional fields: categoryId, merchantName, description, amount, taxAmount, expenseDate, paymentMethod, receiptImageUrl. |
| `ExpenseAllocationDTO` | Read DTO for expense_project_allocations. Fields: id, expenseId, projectId, percentage, createdAt. |
| `CreateExpenseAllocationDTO` | Write DTO. Fields: expenseId, projectId, percentage. |
| `ExpenseCategoryDTO` | Read DTO for expense_categories. Fields: id, companyId, name, icon, isActive, isDefault, sortOrder, createdAt. |
| `CreateExpenseCategoryDTO` | Write DTO. Fields: companyId, name, icon. |
| `ExpenseBatchDTO` | Read DTO for expense_batches. Fields: id, companyId, batchNumber, periodStart, periodEnd, status, totalAmount, expenseCount, reviewedBy, reviewedAt, createdAt. |
| `ExpenseSettingsDTO` | Read/Write DTO. Fields: id, companyId, reviewFrequency, autoApproveThreshold, adminApprovalThreshold, requireReceiptPhoto, requireProjectAssignment, createdAt, updatedAt. |

#### EstimateDTOs.swift

| DTO | Purpose |
|---|---|
| `EstimateDTO` | Read DTO for estimates table. Fields: id, companyId, estimateNumber, opportunityId, projectId, clientId, title, status, subtotal, taxRate, taxAmount, discountPercent, discountAmount, total, notes, validUntil, version, createdAt, updatedAt. Nested: `lineItems: [EstimateLineItemDTO]?`. |
| `EstimateLineItemDTO` | Read DTO for line_items table. Fields: id, estimateId, productId, description, quantity, unitPrice, unit, total, sortOrder, isOptional, taskTypeId, type. |
| `CreateEstimateDTO` | Write DTO. Fields: companyId, opportunityId, clientId, title. |
| `CreateLineItemDTO` | Write DTO. Fields: estimateId, productId, description, quantity, unitPrice, sortOrder, isOptional, taskTypeId, type. |
| `UpdateLineItemDTO` | Partial update DTO. Optional fields: description, quantity, unitPrice, sortOrder, isOptional. |

#### InvoiceDTOs.swift

| DTO | Purpose |
|---|---|
| `InvoiceDTO` | Read DTO for invoices table. Fields: id, companyId, estimateId, opportunityId, projectId, clientId, invoiceNumber, title, status, subtotal, taxRate, taxAmount, total, amountPaid, balanceDue, dueDate, sentAt, paidAt, notes, createdAt, updatedAt. Nested: `lineItems: [InvoiceLineItemDTO]?`, `payments: [PaymentDTO]?`. Note: `lineItems` CodingKey maps to `invoice_line_items`. |
| `InvoiceLineItemDTO` | Read DTO for invoice_line_items table. Fields: id, invoiceId, productId, description, quantity, unitPrice, unit, type, total, sortOrder. |
| `PaymentDTO` | Read DTO for payments table. Fields: id, invoiceId, companyId, amount, method, reference, notes, isVoid, paidAt, createdAt. |
| `CreatePaymentDTO` | Write DTO. Fields: invoiceId, companyId, amount, method, reference, notes. |

#### ProductDTOs.swift

| DTO | Purpose |
|---|---|
| `ProductDTO` | Read DTO for products table. Fields: id, companyId, name, description, unitPrice, costPrice, unit, type, taxable, taskTypeId, isActive, createdAt, updatedAt. |
| `CreateProductDTO` | Write DTO. Fields: companyId, name, description, unitPrice, costPrice, unit, type, taxable. |
| `UpdateProductDTO` | Partial update DTO. Optional fields: name, description, unitPrice, costPrice, unit, type, taxable. |

#### OpportunityDTOs.swift

| DTO | Purpose |
|---|---|
| `OpportunityDTO` | Read DTO for opportunities table. Fields: id, companyId, contactName, contactEmail, contactPhone, jobDescription, estimatedValue, stage, source, projectId, clientId, lossReason, createdAt, updatedAt, lastActivityAt. |
| `CreateOpportunityDTO` | Write DTO. Fields: companyId, contactName, contactEmail, contactPhone, jobDescription, estimatedValue, source. |
| `UpdateOpportunityDTO` | Partial update DTO. Optional fields: contactName, contactEmail, contactPhone, jobDescription, estimatedValue, source, clientId, projectId. |
| `ActivityDTO` | Read DTO for activities table. Fields: id, opportunityId, companyId, type, body, createdBy, createdAt. |
| `CreateActivityDTO` | Write DTO. Fields: opportunityId, companyId, type, body. |
| `FollowUpDTO` | Read DTO for follow_ups table. Fields: id, opportunityId, companyId, type, status, dueAt, assignedTo, notes, createdAt. |
| `CreateFollowUpDTO` | Write DTO. Fields: opportunityId, companyId, type, dueAt, notes. |

### iOS Financial Enums

**Location**: `OPS/OPS/DataModels/Enums/FinancialEnums.swift`

All enums are `String`-backed, `Codable`, and match Supabase column values.

#### EstimateStatus

Cases: `draft`, `sent`, `viewed`, `approved`, `converted`, `declined`, `expired`

Computed helpers:
- `displayName` -- uppercased raw value
- `canSend` -- true for `.draft`
- `canApprove` -- true for `.sent` or `.viewed`
- `canConvert` -- true for `.approved`

#### InvoiceStatus

Cases: `draft`, `sent`, `awaitingPayment` ("awaiting_payment"), `partiallyPaid` ("partially_paid"), `paid`, `pastDue` ("past_due"), `void`

Computed helpers:
- `displayName` -- custom: "AWAITING" for awaitingPayment, "PARTIAL" for partiallyPaid, uppercased raw value otherwise
- `isPaid` -- true for `.paid`
- `needsPayment` -- true for `.awaitingPayment`, `.partiallyPaid`, or `.pastDue`

#### PaymentMethod

Cases: `cash`, `check`, `creditCard` ("credit_card"), `ach`, `bankTransfer` ("bank_transfer"), `stripe`, `other`

Computed helper: `displayName` -- custom formatting for multi-word names (CREDIT CARD, ACH, BANK TRANSFER), uppercased raw value otherwise.

#### LineItemType

Cases: `labor` ("LABOR"), `material` ("MATERIAL"), `other` ("OTHER")

Note: Raw values are uppercase (matches Supabase column values).

#### FollowUpType

Cases: `call`, `email`, `meeting`, `quoteFollowUp` ("quote_follow_up"), `invoiceFollowUp` ("invoice_follow_up"), `custom`

Computed helper: `icon` -- returns SF Symbol name for each type (phone.fill, envelope.fill, person.2.fill, doc.text.fill, receipt, bell.fill).

#### FollowUpStatus

Cases: `pending`, `completed`, `skipped`

#### SiteVisitStatus

Cases: `scheduled`, `completed`, `cancelled`

#### ExpenseStatus

Cases: `draft`, `submitted`, `approved`, `rejected`, `reimbursed`

Computed helpers:
- `displayName` -- uppercased raw value
- `color` -- status-appropriate color (tertiaryText for draft, warning for submitted, success for approved, error for rejected, primaryAccent for reimbursed)

#### ExpensePaymentMethod

Cases: `cash`, `personalCard` ("personal_card"), `companyCard` ("company_card")

Computed helper: `displayName` -- "CASH", "PERSONAL CARD", "COMPANY CARD"

#### ReviewFrequency

Cases: `perJob` ("per_job"), `weekly`, `biweekly`, `monthly`, `quarterly`

Computed helper: `displayName` -- "PER JOB", "WEEKLY", "BIWEEKLY", "MONTHLY", "QUARTERLY"

#### AccountingSyncStatus

Cases: `pending`, `synced`, `error`

### iOS OCR Service

**Location**: `OPS/OPS/Services/ExpenseOCRService.swift`

Protocol-based architecture for receipt OCR:

```swift
protocol ExpenseOCRServiceProtocol {
    func extractReceiptData(from image: UIImage) async throws -> OCRResult
}
```

**OCRResult** struct: `merchantName`, `date`, `total`, `subtotal`, `taxAmount`, `paymentMethod`, `rawText`, `confidenceScores` (per-field confidence 0-1).

**AppleVisionOCRService**: Uses `VNRecognizeTextRequest` with `.accurate` recognition level. Processes all recognized text through `ReceiptParser` which uses regex patterns and heuristics to extract structured fields from raw OCR text.

### iOS BOOKS Tab (Phase 2, May 2026)

**Status:** Reconstructed 2026-05-11 from bug `1b038315`. The Phase 1 4-segment hub (`MoneyDashboardHeader` + `SmartStatCarousel` + `FinancialHealthBar` + Pipeline-in-Books) was replaced by a carousel-led money command center. Pipeline was elevated to its own top-level tab (see `PIPELINE TAB - P1-1`).

**Surface:**
- Lives at iOS `MainTabView.swift` rendering `BooksTabView`. Tab icon `chart.line.uptrend.xyaxis` (unchanged).
- Header: `AppHeader.HeaderType.books` (title "BOOKS").
- Hero: `HeroCarousel` (`OPS/Views/Books/HeroCarousel.swift`) — swipeable 5-card paged surface using `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` (iOS 17+), **not** `TabView(.page)` (avoids spring physics per the OPS motion rule). Cards permission-filtered; last-viewed card persisted via `@AppStorage("books.lastViewedCard")`.

| Card | Question | Period scope | Permission |
|------|----------|--------------|------------|
| `PLCard` | "Am I making money this period?" | Follows selector | `finances.view` |
| `CashFlowCard` | "What's my cash rhythm?" | Follows selector | `finances.view` |
| `ARCard` | "Who do I need to chase?" | Always all-open | `finances.view` |
| `ForecastCard` | "What's coming if pipeline plays out?" | Always active | `pipeline.view` |
| `JobsCard` | "Which jobs make me money? Which lost it?" | Follows selector | `finances.view` |

- Period control: `PeriodPill` (`OPS/Views/Books/Components/PeriodPill.swift`) — single tap-target with 8 options (30D / 90D / 6M / 1Y / MTD / LAST / QTD / YTD).
- Below carousel: 3-segment underline control **INVOICES · ESTIMATES · EXPENSES**. Each renders the existing list view in `embedded: true` mode (unchanged from Phase 1).
- Header collapse: on scroll, the hero collapses to `CollapsedCarouselStrip` (active card's primary number + A/R glance + dots). Segments stick.

**Per-job profitability** (Card 5) computed in `MoneyDashboardViewModel.computeJobNets(periodStart:periodEnd:)`:
- Revenue = `sum(payments.amount)` for invoices with matching `project_id`, paid in-period.
- Cost = `sum(expense_project_allocations.amount)` (with fallback to `expense.amount × percentage / 100` when `amount` is null).
- `expense_project_allocations.project_id` is `text` in Supabase while `invoices.project_id` is `uuid` — both come through as `String` in Swift DTOs, so comparison is string-on-string. Drift D3, reconciled.
- Top 5 = top 4 by net + worst loser if not already present.

**Permission gating:**
- Tab visible if user has any of `finances.view` / `estimates.view` / `expenses.view`. `pipeline.view` no longer gates BOOKS — it gates the new Pipeline tab.
- Carousel hidden entirely when zero cards are permitted (Operator path: `estimates.view` + `expenses.view` only, no `finances.view`, no `pipeline.view`).
- Auto-skip: Crew users with `expenses.view` (own scope) only continue to land on `MyExpensesView` directly via `booksAutoSkipDestination` in `MainTabView`.

**FAB integration:**
- The global `FloatingActionMenu` (`OPS/Views/Components/FloatingActionMenu.swift`) re-orders its MONEY group via `@AppStorage("books.selectedSegment")`. Default changed from `"PIPELINE"` to `"INVOICES"` in Phase 2.
- `add-lead` stays in the MONEY group because the FAB is global — Pipeline being its own top-level tab does not move the create action.

**Spec & plan:**
- Spec: `ops-ios/docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md`
- Plan: `ops-ios/docs/superpowers/plans/2026-05-11-books-ui-reconstruction.md`
- Phase 1 spec (superseded): `ops-ios/docs/superpowers/specs/2026-05-07-books-tab-design.md`

**Phase 1 historical record:** the 4-segment hub (Pipeline + Estimates + Invoices + Expenses), `MoneyDashboardHeader`, `SmartStatCarousel`, `FinancialHealthBar`, `PeriodToggle` were the shipped shape from 2026-05-07 until 2026-05-11. All four Money components were deleted in the Phase 2 cleanup; the May 7 spec is marked superseded.

**Future work (not in scope of Phase 2):**
- Forward cashflow projection (Card 6) — spawned as `CASHFLOW FORECAST - P1-1`.
- Smart-default card surfacing (open most-urgent card by data condition) — Books v2.
- Full-screen reports drilled from Card 2 (Avg/wk, Days) and Card 5 (Profitable, Losers) tiles — currently stubbed.

---

**Last Updated**: February 28, 2026
**Document Version**: 1.3
**Source**: ops-web git commits `0b268fd`, `2742b60`, `f5a01f1`, `81577c4`; iOS source `OPS/OPS/`; Supabase Edge Functions `accounting-oauth`, `accounting-sync-expense`, `accounting-batch-create`
