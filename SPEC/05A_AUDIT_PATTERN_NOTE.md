# SPEC — Operator-Action Audit Pattern (2026-05-26)

Standalone rule. Companion to [SPEC/05_ADMIN_UX.md](05_ADMIN_UX.md). This file exists as a separate document so the rule can land while the main `05_ADMIN_UX.md` is still under sibling edit. When `05_ADMIN_UX.md` next absorbs an editorial pass, the rule below should be folded in as a top-level "Audit conventions" section, and this file can be deleted.

## The rule

SPEC has two audit destinations for operator-driven writes. They serve different scopes and must NOT be confused.

| Operator action scope                                             | Audit destination          | Required fields                                                                                                                                                              |
|-------------------------------------------------------------------|----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Per-project operator events** — status changes, manual milestone fire, feature pass/fail, entitlement toggle, scope revision, communications log entries, refund decisions, hold transitions | `public.spec_communications` | `spec_project_id` (NOT NULL), `direction='outbound'`, `channel='system'` for automated audit rows (or `'admin_note'` for manual operator notes), `summary`, `body` (optional jsonb payload as text), `logged_by_user_id` (the operator's user id), `occurred_at` |
| **Global / multi-project operator config changes** — capacity edits (`spec_capacity`), role grants (`role_permissions`, `user_roles`, `user_permission_overrides`), blocklist edits (`spec_blocked_buyers`), and any future global toggles that don't belong to a single engagement | `public.audit_log`         | `company_id = OPS_OPERATIONS_COMPANY_ID = '00000000-0000-0000-0000-00000000000a'`, `table_name = '<edited table>'`, `record_id = <edited row id>`, `action = 'UPDATE'` (or `'CREATE'` / `'DELETE'` — live CHECK requires UPPERCASE), `old_data` (jsonb of pre-image), `new_data` (jsonb of post-image), `changed_by = <operator user_id>`, `occurred_at` |

## Why both destinations

`spec_communications.spec_project_id` is `NOT NULL`. The column was designed to scope every row to a specific engagement so per-project audit reads and dispute-evidence assembly can use a single-table query. Global config changes — capacity ceilings, role grants, blocklist edits — have no `spec_project_id` because they affect more than one engagement (or none yet). Forcing them through `spec_communications` would require either inventing a sentinel project id (which would break every `spec_project_id` join) or relaxing the `NOT NULL` constraint (which would weaken every per-project query).

`public.audit_log` already exists for cross-table, cross-company config audit. It carries `company_id` (the company whose data was affected — for SPEC global config, that's the OPS Operations company), `table_name`, `record_id`, `action`, `old_data`, `new_data`, `changed_by`. Stage F.4 picked this destination when implementing the capacity audit because the capacity table is operator-global and the `spec_communications` shape did not fit.

## Practical examples

**Capacity edit** (`/admin/spec/capacity` operator changes the `setup` tier's `slot_ceiling` from 4 to 6):

```sql
-- audit_log row written inside the same transaction as the spec_capacity update
insert into public.audit_log (id, company_id, table_name, record_id, action, old_data, new_data, changed_by, occurred_at)
values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-00000000000a',                  -- OPS_OPERATIONS_COMPANY_ID
  'spec_capacity',
  null,                                                    -- spec_capacity uses tier as PK (text); store the tier value in new_data instead
  'UPDATE',
  jsonb_build_object('tier', 'setup', 'slot_ceiling', 4),
  jsonb_build_object('tier', 'setup', 'slot_ceiling', 6),
  '<operator user_id>',
  now()
);
```

**Per-project status change** (operator manually flips a project from `discovery` to `building`):

```sql
-- spec_communications row written as part of the status-change server action
insert into public.spec_communications (id, spec_project_id, direction, channel, summary, body, logged_by_user_id, occurred_at)
values (
  gen_random_uuid(),
  '<spec_project_id>',
  'outbound',
  'system',
  'Status changed: discovery → building',
  jsonb_build_object(
    'from_status', 'discovery',
    'to_status', 'building',
    'reason', 'scope_doc_signed_at stamped'
  )::text,
  '<operator user_id>',
  now()
);
```

**Blocklist edit** (operator adds a new email to `spec_blocked_buyers`):

```sql
-- audit_log row; spec_blocked_buyers is global, not per-project
insert into public.audit_log (id, company_id, table_name, record_id, action, old_data, new_data, changed_by, occurred_at)
values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-00000000000a',                  -- OPS_OPERATIONS_COMPANY_ID
  'spec_blocked_buyers',
  '<new spec_blocked_buyers.id>',
  'CREATE',
  null,
  jsonb_build_object('email', 'evil@example.com', 'blocked_reason', 'chargeback_history'),
  '<operator user_id>',
  now()
);
```

## Decision matrix

When implementing a new operator action, ask: "Does this write touch exactly one engagement's data?"

- **Yes, exactly one engagement** → write to `spec_communications`. Carry `spec_project_id`. Channel is `'system'` for code-driven rows, `'admin_note'` for free-text operator notes.
- **No — it's a global config change, or it spans multiple engagements** → write to `audit_log`. Carry `company_id = OPS_OPERATIONS_COMPANY_ID`, `table_name`, `record_id`, `action` (UPPERCASE).
- **Both — for example, a single operator action edits one project AND a global config row** → write TWO rows: one `spec_communications` row scoped to the project, one `audit_log` row for the global change. They live in different tables on purpose; don't try to collapse them.

## Cross-references

- Capacity audit implementation: Stage F.4 in [`04_API_AND_INTEGRATION.md`](../04_API_AND_INTEGRATION.md) (look for `/admin/spec/capacity` and the audit_log write).
- `audit_log` table shape: [`public.audit_log`](../03_DATA_ARCHITECTURE.md) — `company_id` `text`, `table_name` `text`, `record_id` `uuid`, `action` `text` (UPPERCASE check), `old_data` `jsonb`, `new_data` `jsonb`, `changed_by` `text`, `occurred_at` `timestamptz`.
- `spec_communications` table shape: [`SPEC/02_DATA_MODEL.md`](02_DATA_MODEL.md) `## Core tables` → table 13.
- `OPS_OPERATIONS_COMPANY_ID` constant: defined in [`SPEC/02_DATA_MODEL.md`](02_DATA_MODEL.md) `## OPS Operations internal company` — value `'00000000-0000-0000-0000-00000000000a'`.
