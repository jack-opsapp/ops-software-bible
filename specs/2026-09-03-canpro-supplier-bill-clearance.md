# Canpro supplier bill clearance

**Designed:** 2026-09-03
**Documented:** 2026-09-04
**Status:** Production database and OPS-Web source are released on production main as of 2026-09-04. iOS remains local/unreleased.

## Purpose

Provide one durable path from a supplier PDF to a reviewed liability, without treating an unread or unapproved document as an expense or provider-ready bill.

The operator sequence is:

`capture → extract → reconcile → hold or approve → schedule → record payment`

Employee documents branch from review to payroll and never enter accounts payable.

## Product boundary

- Capture immediately preserves the original PDF and extracted source facts.
- Extraction and rule matches are suggestions. An operator supplies every consequential disposition.
- Review and held states remain outside canonical AP and provider sync.
- Approval is the first transaction allowed to create a canonical supplier bill and provider queue work.
- Web owns dense reconciliation, hold, approval, payroll routing, and payment work.
- iOS owns durable field capture and read-only review of server-authoritative results.
- Already-paid purchases continue through the released expense flow; this intake contract handles documents that require clearance before payment.

## Document classification and required checks

| Kind | Required checks | Allowed destination |
|---|---|---|
| Material | Rate applicability, duplicate billing, quantity/scope, order/specification, receipt | AP after approval |
| Subcontractor | Rate compliance, duplicate billing, quantity/scope | AP after approval |
| Employee | Duplicate billing | Payroll only |

Canpro's labour rate card applies only to subcontractor labour:

- Slick or smooth vinyl: maximum CAD 2.25 per sq ft.
- Fuzzy vinyl: maximum CAD 2.00 per sq ft.
- Diverter or scupper work: maximum CAD 25 each.
- Drain work: maximum CAD 15 each.

Material unit prices must never be compared to this labour card. The material `rate_compliance` record exists to make that distinction explicit and must be dispositioned as not applicable with evidence. A detected rate, duplicate, or quantity issue is not an automatic rejection; it is an exception that requires an operator note, acceptance, or hold.

## Lifecycle

- `review`: source is durable; facts, matches, allocations, and checks may still need work.
- `held`: a reason and next action are both required. No AP or provider work exists.
- `to_pay`: a material or subcontractor intake has passed approval, was promoted exactly once to canonical AP, and has an owner and planned payment date.
- `paid`: payment was recorded against the live canonical balance.
- `payroll`: an employee document was routed out of AP. No supplier bill or provider queue row exists.

A supplier's printed due date remains nullable. OPS never infers it. The planned payment date is an internal operating commitment and is stored separately.

## Reconciliation rules

Line evidence preserves invoice order, SKU, description, ordered quantity, invoiced quantity, unit of measure, unit price, subtotal, tax, total, job hint, and provenance. Address and purchase-order matches remain suggestions until a human confirms a same-company project.

Every approved line must be allocated exactly to one or more same-company projects. Shared charges receive an exact-cent suggestion proportional to material subtotals; deterministic remainder assignment makes the allocations sum to the line total. An operator can replace the suggestion with an exact manual allocation.

Approval requires:

1. Every classification-required check has a non-unresolved disposition.
2. Every accepted exception contains a note.
3. Every line has exact confirmed allocations totaling the line amount.
4. Payment owner and planned payment date are present.
5. The intake is still at the expected revision and has not already been promoted.

## Data and security contract

OPS-Web source migrations:

- `ops-web/supabase/migrations/20260904040358_supplier_bill_intake_clearance.sql`
- `ops-web/supabase/migrations/20260904171534_supplier_bill_intake_fk_indexes.sql`
- `ops-web/supabase/migrations/20260904190000_supplier_bill_company_data_lifecycle.sql`

Production ledger mirrors:

- `migrations/20260904171301_supplier_bill_intake_clearance.sql` — 52,199 bytes, MD5 `c1999781a038c5b4669780f3b0f02c9a`.
- `migrations/20260904171632_supplier_bill_intake_fk_indexes.sql` — 2,249 bytes, MD5 `7ebe982a2e7d05e1d6054f673a7c84a4`.
- `migrations/20260904184303_supplier_bill_company_data_lifecycle.sql` — 5,396 bytes, MD5 `a83e020320704457be9c7abd749f0e44`.

Production ledger `20260904184303_supplier_bill_company_data_lifecycle` is a byte-exact mirror of the third source migration. It keeps all four immutable supplier document/event tables non-deletable during ordinary service work while allowing the service-role-only `purge_company_rows` account-closure transaction to erase them. Deleting either supplier event ledger also erases its matching private prepared-write intents in the same transaction. The helper now covers the complete 42-table delete-blocked set, and the optional site-visit handoff provenance clears instead of blocking a company purge.

Public tables:

- `supplier_bill_intakes`
- `supplier_bill_intake_line_items`
- `supplier_bill_intake_allocations`
- `supplier_bill_intake_checks`
- `supplier_bill_intake_documents`
- `supplier_bill_intake_events`

Private table: `private.supplier_bill_intake_write_intents`.

Reads require current company membership and `accounting.view`. Capture/review, approval, and payment are independently authorized by `accounting.bills.capture`, `accounting.bills.approve`, and `accounting.bills.pay`. Owners and admins receive all three; supervisors receive capture and pay but not approval.

All writes pass through `prepare_supplier_bill_intake_write` and `commit_supplier_bill_intake_write`. Both are security-definer functions with an empty `search_path`, full schema qualification, and service-role-only execution. The intent binds company, actor, action, request identity, command SHA-256, expected revision, exact confirmation text, and a 15-minute expiry. Commit reauthorizes and returns a fresh receipt. Documents and events are insert/read-only for the service role; authenticated clients have tenant-scoped reads and no direct writes.

## HTTP contract

Source routes introduced in OPS-Web commit `ca7f46f3c`, first deployed in `f0464eedf`, and published on production main in `f901c6d9c`:

- `POST src/app/api/internal/accounting/supplier-bills/intakes/route.ts` — multipart capture.
- `GET src/app/api/internal/accounting/supplier-bills/intakes/route.ts` — lifecycle summaries.
- `GET src/app/api/internal/accounting/supplier-bills/intakes/[intakeId]/route.ts` — full detail.
- `POST src/app/api/internal/accounting/supplier-bills/intakes/[intakeId]/prepare/route.ts` — prepare review/hold/approval/payroll/payment action.
- `POST src/app/api/internal/accounting/supplier-bills/intakes/[intakeId]/commit/route.ts` — exact-confirmation commit.

Authentication uses the current Firebase actor. Repository reads and writes remain company-scoped. PDFs must identify as PDF, be no larger than 20 MB, and enter immutable S3 custody. Parsing is local through `pdfjs-dist`; no external extraction provider is added.

## Client behavior

OPS-Web commit `bf3610e3e` adds Bills to Books, lifecycle filters, a capture surface, list/detail review, clearance checks, lines and allocations, hold/release, approval, payroll routing, and payment work. Action visibility follows the independent permissions. The source and its account-closure integration are published on production main at `f901c6d9c0e1bd63abddcb616a697f7fb9115ad6` through Git-triggered Vercel deployment `dpl_7BCJY52J5SB6KwmY7qdCrLSzCUH3`, which is `READY` and owns `app.opsapp.co`.

OPS iOS local commit `c6269763` adds Bills to Books, PDF import, VisionKit scan-to-PDF, a protected company-scoped capture queue, a protected company-scoped summary/detail cache, five lifecycle filters, and read-only detail. Each queued PDF has a stable capture identity, survives relaunch and transient connectivity, and is removed only after the same identity is confirmed by the server. Permanent rejection retains the local source and requires attention. Cached data remains explicitly marked as an offline copy.

Key iOS files:

- `OPS/DataModels/SupplierBillIntake.swift`
- `OPS/Services/SupplierBills/SupplierBillCaptureQueue.swift`
- `OPS/Services/SupplierBills/SupplierBillCache.swift`
- `OPS/Services/SupplierBills/SupplierBillIntakeService.swift`
- `OPS/ViewModels/SupplierBillIntakeViewModel.swift`
- `OPS/Views/Books/Bills/SupplierBillsView.swift`

## Release boundary and cost

Jackson approved the production database migration, source publication, Bible publication, and OPS-Web deployment on 2026-09-04. All three supplier-intake migrations are applied and the Git-triggered web deployment is `READY` at exact production-main commit `f901c6d9c0e1bd63abddcb616a697f7fb9115ad6` on `app.opsapp.co`. Release readback proved all six public intake tables have RLS, browser roles have company-scoped reads and no direct writes, guarded RPC execution is service-role-only, immutable documents/events remain insert/read-only for ordinary service work, and all 37 supplier-bill foreign-key repair indexes are present. The 267-table company-data scope and the 42-table delete-blocked snapshot match production exactly. Both private intent tables and all 17 public supplier/intake tables remained empty. Security advisors report no finding related to supplier bills, `purge_company_rows`, or the site-visit handoff foreign key.

The OPS-Web source is on production main. The iOS implementation remains local and unreleased; it still requires a separate iOS release approval.

`pdfjs-dist`, PDFKit, and VisionKit run locally and add no usage-priced vendor. The release introduces no new subscription; it uses the existing S3, Vercel, and Supabase infrastructure and is subject only to their ordinary storage, transfer, function, and database consumption.
