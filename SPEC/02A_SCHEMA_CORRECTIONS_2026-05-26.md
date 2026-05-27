# SPEC — Schema Corrections (2026-05-26)

Standalone correction note. Companion to [SPEC/02_DATA_MODEL.md](02_DATA_MODEL.md). This file exists as a separate document so the corrections can land while the main `02_DATA_MODEL.md` is still under sibling edit. When `02_DATA_MODEL.md` next absorbs an editorial pass, the rules and mappings below should be folded into the relevant column documentation, and this file can be deleted.

All corrections below are sourced from the live Phase 1 SPEC schema as applied via the `migrations/2026-05-25-spec-phase1-*.sql` set, the Stage C.2 webhook handler commit at [`ops-site@85c5fec`](https://github.com/) `feat(spec/webhook): Phase 1 SPEC deposit + dispute webhook handler`, the Stage C.3 owner-approval route at [`04_API_AND_INTEGRATION.md:2037`](../04_API_AND_INTEGRATION.md), and the Stage F.2.a fire-milestone server action at [`04_API_AND_INTEGRATION.md:2444`](../04_API_AND_INTEGRATION.md).

---

## 1. `spec_acceptance_events.signature_method` — `click_in_app` for Stripe Checkout completion

**Live constraint** ([`migrations/2026-05-25-spec-phase1-04-core-tables.sql`](../migrations/2026-05-25-spec-phase1-04-core-tables.sql)):

```sql
signature_method text check (signature_method in ('click_in_app', 'docusign', 'email_reply'))
```

**Rule.** Stripe Checkout completion uses `signature_method = 'click_in_app'`. The buyer clicked through Stripe Checkout while authenticated in their browser session — the closest semantic match in the live enum for what Stripe calls `consent_collection`. The Stripe receipt URL is stored in `signature_evidence_url` for the evidence trail. The earlier spec draft that proposed a `'stripe_consent_collection'` value is superseded — that value is NOT in the live CHECK constraint and would be rejected on insert.

**Path B owner-approval** uses the same `'click_in_app'` value for the `'owner_purchase_approved'` acceptance event — the account-holder clicked Approve on the approval page while authenticated. Reference: [`04_API_AND_INTEGRATION.md:2037`](../04_API_AND_INTEGRATION.md) (Stage C.3 approve branch).

**Path A buyer ToS acceptance** at Stripe Checkout completion also uses `'click_in_app'`. Reference: [`04_API_AND_INTEGRATION.md:1959`](../04_API_AND_INTEGRATION.md) (Stage C.2 normal deposit_paid flow).

If a future migration adds a `'stripe_consent_collection'` enum entry, both webhook handlers and the bible can adopt it — until then, `'click_in_app'` is the canonical value for every Stripe-driven acceptance event.

---

## 2. `spec_payments.milestone` — display labels vs enum values

**Live enum** ([`migrations/2026-05-25-spec-phase1-01-enums-and-capacity.sql:36`](../migrations/2026-05-25-spec-phase1-01-enums-and-capacity.sql)):

```sql
create type spec_payment_milestone as enum (
  'deposit',
  'scope_signoff',
  'midpoint',
  'delivery'
);
```

**Display-label mapping.** Customer-facing copy, operator dictionary, and `/admin/spec` UI text use the four-character labels `P1` / `P2` / `P3` / `P4`. These are display strings only — NOT DB enum values. DB writes always use the enum values above.

| Display label | DB enum value     | Trigger                                          |
|---------------|-------------------|--------------------------------------------------|
| P1            | `deposit`         | Stripe Checkout completion (Stage C.2 webhook)   |
| P2            | `scope_signoff`   | Operator fires after scope sign-off (Stage F.2.a)|
| P3            | `midpoint`        | Operator fires after midpoint acceptance (F.2.a) |
| P4            | `delivery`        | Operator fires after walkthrough completion (F.2.a)|

**Rule.** Any code path that needs to set `spec_payments.milestone` MUST use one of the four enum values above. Display copy may continue to use `P1`..`P4` shorthand. Mixing the two — for example, inserting `milestone='P1'` — fails the enum constraint at write time.

If a Supabase query against the live DB ever returns enum values that differ from `deposit | scope_signoff | midpoint | delivery` (for example, `scope` or `demo` in place of `scope_signoff` and `midpoint`), that is an applied-vs-source drift between the live DB and `migrations/2026-05-25-spec-phase1-01-enums-and-capacity.sql`. Open a follow-up to align the live DB with the migration before further code changes touch these enums.

---

## 3. `spec_projects.tos_accepted_ip` — always NULL in Phase 1

**Reason.** Stripe Checkout Sessions do not propagate the customer's IP through any field on the `checkout.session.completed` payload. The `customer_details` object exposes `address`, `email`, `name`, `phone`, and `tax_ids` — none of which include an IP. The Stage C.2 webhook handler therefore stores `tos_accepted_ip = NULL` on the `spec_projects` row, and `accepted_ip = NULL` on the corresponding `spec_acceptance_events` row.

**Rule.** Until a future change routes checkout completion through a server-side polling endpoint that captures the request IP, both `spec_projects.tos_accepted_ip` and `spec_acceptance_events.accepted_ip` will be NULL for every Stripe-completed Path A acceptance event. Documented at [`04_API_AND_INTEGRATION.md:1957`](../04_API_AND_INTEGRATION.md) and [`04_API_AND_INTEGRATION.md:1998`](../04_API_AND_INTEGRATION.md).

**Path B (owner-approval) IP capture.** The Stage C.3 approval-page POST DOES capture the request IP from the inbound request headers and stores it on `spec_owner_approval_requests.decided_ip` and on the `spec_acceptance_events.accepted_ip` for the `owner_purchase_approved` event. Reference: [`04_API_AND_INTEGRATION.md:2035`](../04_API_AND_INTEGRATION.md).

Phase 2 MAY add IP capture for Path A by introducing a server-side completion endpoint that polls the Stripe Session after redirect; this would let the deposit-paid handler stamp the IP from the inbound browser request. For Phase 1, NULL is the canonical state and is NOT a defect.

---

## 4. Dispute columns on `spec_projects` — deferred to Phase 2

**Bible spec called for** three columns on `spec_projects`:

- `has_active_dispute boolean default false`
- `dispute_opened_at timestamptz`
- `guarantee_window_closed_at timestamptz`

**Live schema does not carry these columns.** The Stage C.2 dispute handler ([`ops-site/src/lib/spec/webhook-handlers.ts`](https://github.com/) `charge.dispute.created` branch) workarounds the absence by writing the dispute evidence trail across three existing tables:

| Side effect                | Table + write                                                                                                       |
|----------------------------|---------------------------------------------------------------------------------------------------------------------|
| Mark the payment disputed  | `update spec_payments set status='disputed' where stripe_payment_intent_id = $1`                                    |
| Revoke module access       | `update spec_module_entitlements set enabled=false, disabled_reason='dispute', disabled_at=now() where spec_project_id = $1` |
| Persist the evidence chain | `insert into spec_communications (direction='outbound', channel='system', summary='Stripe dispute opened — {reason}', body=$dispute_payload, ...)` |
| Operator alert             | `insert into public.notifications (type='spec_dispute_opened', persistent=true, company_id=OPS_OPERATIONS_COMPANY_ID, ...)` (one row per SPEC operator) |
| Customer alert             | `insert into public.notifications (type='spec_dispute_opened', persistent=true, company_id=linked_company_id, action_url='/account/spec/{id}/request-refund', ...)` |

**Decision (2026-05-26): canonical Phase 1 pattern. No migration.** The three flag columns are NOT added in Phase 1. The four-table workaround above is the canonical dispute representation through Phase 1.

**Why no migration:**
1. The workaround works — every downstream consumer (operator notification, entitlement revocation, refund evidence package) reads from the existing rows.
2. Adding three nullable columns + the trigger logic to keep them coherent with `spec_payments.status` and `spec_module_entitlements.disabled_reason` is non-trivial; the columns would have to be backfilled atomically with status flips, and any code path that flips the status WITHOUT flipping the flags would create stale state.
3. Dispute volume in Phase 1 is expected to be single-digit per quarter; per-dispute JOIN cost across `spec_communications + spec_payments + spec_module_entitlements` is well within Supabase's nominal query latency for an operator dashboard read.

**Phase 2 trigger to revisit:** if dispute-evidence assembly proves slow at higher volume (operator dashboard queries that JOIN across the three tables exceed ~250ms p95), add the three flag columns in a Phase 2 migration AND wire `triggers` or service-route invariants to keep them coherent with the existing four-table writes. Document the migration as a denormalization for read performance — the existing four-table writes remain authoritative.

---

## 5. Cross-references

- Schema source-of-truth: [`SPEC/02_DATA_MODEL.md`](02_DATA_MODEL.md) (the section anchors `## Core tables`, `## RLS and server-route default`).
- Webhook implementation: Stage C.2 in [`04_API_AND_INTEGRATION.md`](../04_API_AND_INTEGRATION.md) (look for `## Stage C.2`).
- Owner-approval implementation: Stage C.3 in [`04_API_AND_INTEGRATION.md`](../04_API_AND_INTEGRATION.md) (look for `POST /api/spec/owner-approval/[token]`).
- Fire-milestone implementation: Stage F.2.a in [`04_API_AND_INTEGRATION.md`](../04_API_AND_INTEGRATION.md) (look for `_actions/fire-milestone.ts`).
- Audit pattern for capacity edits and other global config writes: [`SPEC/05A_AUDIT_PATTERN_NOTE.md`](05A_AUDIT_PATTERN_NOTE.md).
