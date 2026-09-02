# OPS MCP Payroll Readiness Vertical

- **Designed:** 2026-09-01
- **Status:** Local release candidate; dormant and unapplied
- **Authoritative Web base:** `cd3082a3f0318c3c56649b78244851f539a651d2`
- **Phase 6 Web commit:** `50bd43bcaee080de310eee9ad7d18325b37d0738`
- **Authoritative Bible base:** `9fb95501ec0c2bad7c86cc7c4f78066378659af0`
- **Source migration:** `ops-web/supabase/migrations/20260901190000_agent_payroll_readiness.sql`
- **Bible mirror:** `supabase/migrations/20260901190000_agent_payroll_readiness.sql`

## Purpose

The sixth Invisible Office vertical answers one bounded question:

> Can I make payroll on the 15th?

`check_payroll_readiness` is a read-only cash control sheet, not a banking integration or a promise that customers will pay. It accepts one exact company-local target date. OPS owns the tenant, observation time, cash source, payroll and obligation definitions, payer-history model, source window, evidence requirements, and decision rules.

The answer is one of:

- `yes`: complete decision-critical evidence and current cash alone cover every OPS-recorded obligation through the payroll cutoff;
- `no`: complete evidence and even the best modeled receivable case finishes below zero;
- `at_risk`: complete evidence crosses zero between the cash-only floor and modeled receivable cases; or
- `insufficient_evidence`: a missing, stale, inconsistent, ambiguous, or bounded source could change the answer.

## Immutable contracts

- Result schema: `2026-09-01.v1`
- Metric definition: `payroll-readiness:2026-09-01.v1`
- Capability manifest: `2026-09-01.capability-manifest.v14`
- Dormant exposure: `2026-09-01.mcp-exposure.v8`
- Tool: `check_payroll_readiness`
- Tool input: exactly `{ "target_date": "YYYY-MM-DD" }`
- Projection horizon: current company-local business date through 93 days ahead
- Cash and scheduled-obligation confirmation freshness: 24 hours
- Minimum payer sample: five fully settled invoices for the same canonical `client_id`

Manifest v14 re-mints v13 and adds only this high-stakes read. Exposure v8 is additive to v7: `analyze_hiring_break_even`, `check_customer_reply`, `analyze_sales_truth`, and `check_payroll_readiness`. Its scope ceiling is byte-identical to v7. Active production exposure remains v2.

## Authoritative data

Available cash comes only from `expense_settings.forecast_current_balance`, with capture time `forecast_balance_updated_at`, in `companies.currency_code`. This is the existing operator-maintained forecast balance. OPS does not claim that it is a bank feed. Signed values are valid: a negative recorded balance is a truthful deficit, not malformed input.

The additive migration proposes four nullable fields:

| Table                | Column                                   | Type                     | Meaning                                                                                 |
| -------------------- | ---------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------- |
| `expense_settings`   | `forecast_obligations_confirmed_through` | `date`                   | Last company-local date through which scheduled obligations were confirmed complete.    |
| `expense_settings`   | `forecast_obligations_confirmed_at`      | `timestamptz`            | Exact confirmation instant. Both confirmation fields must be null or non-null together. |
| `recurring_expenses` | `obligation_kind`                        | `text`                   | Closed nullable classification: `payroll` or `other`; null means not classified.        |
| `recurring_expenses` | `due_time_local`                         | `time without time zone` | Exact due time in the company timezone; null means timing is unknown.                   |

Scheduled obligations come from active `recurring_expenses`. The source RPC deliberately retains malformed active cadence and date-range rows so the application can return `obligation_schedule_invalid`; blank, oversized, or unsupported cadence/currency text is converted to a bounded invalid sentinel instead of making the repository unavailable or hiding the row. Non-finite and finite-but-noncanonical years are retained under the same fail-closed source contract. Valid recurrences expand from `next_due_date` by the stored cadence, preserve literal years 0001-9999, and allow at most 32 occurrences per obligation before the calculation fails closed. A recorded overdue occurrence remains owed and is included; passing the current business date never deletes it from the calculation. Payroll must be explicitly classified and due on the requested target date. The payroll cutoff is the latest payroll due time that day. A same-day non-payroll obligation counts only when its exact due time is at or before that cutoff. Once a same-day cutoff has passed, the answer is `insufficient_evidence`; OPS never uses cash captured after payroll was already due. `time(6)` and `timestamptz(6)` values retain all six fractional digits end-to-end, so same-second due times and same-millisecond confirmation updates remain correctly ordered.

Approved, partially approved, or auto-approved `expense_batches` with `paid_at IS NULL` are current reimbursement obligations. The amount exactly matches the product's canonical `batchOwedAmount` rule: partial approval uses `approved_amount` when present, including zero, then falls back to `total_amount`; full or automatic approval uses a positive `approved_amount`, otherwise `total_amount`; all absent values resolve to zero and are still subjected to amount validation. Linked non-deleted expense lines must prove one company currency.

Open receivables are non-deleted invoices in `sent`, `awaiting_payment`, `partially_paid`, or `past_due`. OPS recomputes the as-of balance as invoice total less non-void payments dated on or before the company-local business date and compares it with stored `amount_paid` and `balance_due`. Future-dated payments never alter the snapshot. A mismatch, invalid amount/date, future delivery timestamp, or duplicate non-null provider identity is an integrity gap and the receivable is not modeled.

Historical payer delay is based on durable net settlement. Non-void as-of payments of every sign are aggregated by invoice and payment date before a cumulative balance is calculated. Settlement is the first date from which the cumulative balance remains at or above invoice total through every later adjustment. A same-day payment and reversal therefore net before settlement, and a later credit or reversal invalidates an earlier apparent paid date until the balance is durably restored. `NaN`, infinite, or overlong invoice/payment amounts remain visible as invalid history and never enter a payer distribution. Delay is the safe integer `settled_on - due_date`, grouped by canonical `client_id`, with no arbitrary ten-year cap. `invoice.paid_at` and an invoice due date alone never become payment evidence.

## Projection rules

All PostgreSQL decimals cross the application boundary as strings capped at 64 characters. `NaN`, infinities, and wider values are normalized to `__invalid__` before contract parsing. Currency exponents come from the exhaustive, version-frozen ISO 4217 List One table already owned by the agent contract; unknown codes and fund/metal/test units without a supported minor-unit meaning fail closed. The application accepts only amounts exactly representable in that minor unit. Individual values become safe integer minor units, all totals and scenario arithmetic accumulate as `bigint`, and any unsafe emitted aggregate returns `financial_total_overflow`. It never uses floating-point money, rounds excess precision, or converts currencies.

For each payer with at least five valid settlements:

- best case uses empirical nearest-rank p25 delay;
- base case uses empirical nearest-rank p50 delay;
- p75 is disclosed as evidence; and
- worst case includes zero receivable cash because a historical distribution is not a collection guarantee.

A projected receipt on the payroll date is excluded because invoices have date precision, not an intraday arrival time. Projection arithmetic must remain a canonical date in years 0001-9999; an out-of-range result is explicitly unmodeled. If the best projected arrival date has already passed while the invoice remains open, OPS does not roll the missed prediction forward; the invoice becomes unmodeled. Unknown receivables force `insufficient_evidence` only when the cash-only outcome is negative and those unknowns could change the decision.

The result itemizes every counted obligation occurrence with date, local due time, exact amount, kind, and source reference. Every open receivable carries its reconciled balance, payer reference, p25 and p50 arrival dates when modelable, and explicit best/base inclusion flags. Result validation independently re-derives typed provenance, unique payer samples, item/ref sets, source bounds, exact sums, temporal inclusion, cash freshness, company-local horizon, completeness state, and the final decision. An unrelated overflow or evidence-gap label cannot authorize altered arithmetic. These facts make each scenario independently auditable without trusting aggregate reference lists alone.

## Authority and database boundary

The read requires these OAuth scopes:

- `ops.company.read`
- `ops.expenses.read`
- `ops.financial_documents.read`
- `ops.financials.read`
- `ops.payments.read`

It also requires current company-wide `expenses.view`, `invoices.view`, `reports.view`, and `settings.company` permissions.

The application re-resolves the already validated MCP actor immediately before the repository call. `public.read_agent_payroll_readiness_as_system(...)` then independently rechecks the actor, company, OAuth client and grant, exact grant revision and scope ceiling, consent labels, permission snapshot, manifest v14, exposure v8, capability id, and capability revision before reading business data.

The public RPC is `SECURITY DEFINER`, stable, and search-path pinned. Execute is revoked from `public`, `anon`, and `authenticated`, then granted only to `service_role`. The private authority helper is not executable by app roles.

A private `payroll_readiness` read-domain revision is seeded for every company. Row triggers advance it for `expense_settings`, `recurring_expenses`, `expense_batches`, `expenses`, `invoices`, and `payments`. Company-context revisioning remains separate.

All source collections read one extra row to prove overflow. The limits are aligned to the itemized result contract and its 400,000-character ceiling:

- 40 recurring obligations;
- 50 reimbursement batches;
- 100 open receivables; and
- 500 historical settled invoices.

Every decimal scalar is capped at 64 characters, and the repository independently rejects a source snapshot beyond 400,000 characters before schema traversal. Any reached collection bound is decision-critical insufficient evidence. A deterministic maximum-shape application test proves the raw source is 154,555 characters and that 691 supporting records, 1,330 itemized obligations, 100 itemized receivables, and 100 payer distributions serialize to 373,685 result characters. Four guarded partial/composite B-tree indexes support the exact recurring-obligation, reimbursement, open-invoice, and payment-history predicates. The invoice path keys `(company_id, due_date, id)` and includes `client_id`, so the global due-date order does not require a sort. A same-named index with a different key or predicate aborts migration replay.

Migration replay also verifies exact type, nullability, precision, absence of defaults/identity/generated behavior, and exact validated, inheritable constraint definitions and referenced columns for all four metadata fields. A same-named but drifted column, constraint, or index aborts before any release can proceed.

## Prompt safety and effects

Source references are opaque typed identifiers. Returned finance values and references are marked untrusted business data. They cannot choose authority, definitions, tools, SQL, or actions.

The feature performs no runtime DML and creates no durable result, approval, queue item, notification, routine, draft, message, payment, financial document, provider request, model call, or UI.

## Verification evidence

The permanent test suite covers strict input, database-to-agent invalid-target transport, exact tenant/business-date binding across three- and six-digit timestamp formatting, date horizon, the exhaustive currency table, signed cash, exact minor units, checked aggregate overflow, valid/malformed/overdue recurrence obligations including literal years below 0100, microsecond confirmation ordering, subsecond and pre/post same-day payroll cutoff, canonical reimbursement amounts across every accepted status and null/zero/positive approval state, durable as-of settlement chronology including future payments, same-day and later reversals, invalid payer amounts, uncapped imported delay evidence, empirical percentiles, future delivery rejection, same-day/already-missed/out-of-range receivable predictions, every published completeness reason, all four decision states, typed item-level attribution, payer-sample disjointness/bounds, maximum source/result shape, authority revalidation, v1-v7 exposure stability, active-v2 identity, source bounds, exact metadata/default/generated/precision/constraint/index shapes and query-plan use, migration replay, and adversarial result tamper rejection.

A SHA-256-pinned disposable PostgreSQL 17.11 runner proves compile and replay, function volatility/search paths/ACLs, tenant and revoked-grant denial, missing permission denial, exact SQLSTATE `22023` target errors, v14/v8 binding, golden source rows, future-payment exclusion, split payments, negative adjustments, same-day netting, later reversals and recovery, bounded malformed-text/numeric normalization, non-finite and finite-out-of-contract temporal retention, microsecond/subsecond transport, canonical reimbursement amounts, invalid-history exclusion, revision triggers, metadata constraints, all four ordered index plans, source overflow, and rejection of drifted same-named columns, defaults, generated expressions, precisions, constraints, and indexes.

## Cost boundary

This local candidate adds no paid service, model call, scheduled job, or durable analytical storage. If deployment is separately approved, the four indexes consume ordinary existing PostgreSQL storage and add maintenance work only to qualifying source-table writes. Each tool call performs one bounded service-role read.

## Release boundary

As verified on 2026-09-01, production has one active v2 client and one active v2 grant, zero v8 clients/grants, none of the four proposed columns, and no payroll-readiness RPC. Phase 6 does not push, deploy, apply the migration, register a client, mint a grant, change OAuth discovery, or activate exposure v8.

A later release requires separate explicit approval for push/deployment and migration application. Client registration, user consent/grant creation, controlled authenticated tool proof, activation, and customer-live status remain separate gates after release.

## Production release update — 2026-09-02

The schema and application are production-released in OPS-Web `a763f1a0`, with production ledger `20260902194727_agent_payroll_readiness`. The four guarded metadata columns are present, the live function remains service-role-only, and v8 has zero clients and zero grants. Active production exposure remains read-only v2; this vertical is deployed but dormant, not host-accepted or customer-live. The release record in `specs/2026-09-02-ops-mcp-phases-3-7-production-release.md` supersedes the earlier local-only release boundary.
