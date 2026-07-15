# SPEC — Data Model

Full Supabase schema for SPEC. Tables are drafted for the existing `ops-app` Supabase project (`ijeekuhbatykdomumfjx`), shared with OPS-Web and the iOS app. Fourth-pass implementation rule: customer-facing SPEC reads/writes use server routes returning narrow projections in Phase 1. Raw SPEC tables are operator/service-role owned unless a migration intentionally exposes a specific constrained path.

Verified against the live identity model on 2026-05-25 (Supabase MCP queries against `ijeekuhbatykdomumfjx`):
- `public.users.id` is `uuid`.
- `public.companies.account_holder_id` is `text` (stores `users.id::text`).
- `public.companies.admin_ids` is `text[]` (stores `users.id::text` values).
- `public.companies` NOT NULL columns with defaults: `timezone='America/Vancouver'`, `locale='en'`, `ai_enabled=true`, `currency_code='CAD'`, `default_work_start='08:00:00'`, `default_work_end='17:00:00'`. The OPS Operations seed inserts only `(id, name, created_at)`; defaults cover the rest.
- `public.companies.slug` does NOT exist (verified). SPEC does not reference it.
- `public.get_user_id()` returns `text` (reads `auth.jwt() ->> 'email'`, SECURITY DEFINER).
- `public.has_permission(p_user_id uuid, p_permission text, p_required_scope text DEFAULT 'all')` exists; SECURITY DEFINER. **Confirmed body short-circuits to `true` for any user matching `is_company_admin`, `account_holder_id`, or `admin_ids`, BEFORE consulting `role_permissions`** — making it unsafe as the SPEC operator gate. SPEC defines `private.is_spec_operator()` instead (§ Operator gate below).
- `public.role_permissions(role_id, permission, scope)`: all NOT NULL; `scope` values in live data are `'all'` (280), `'own'` (19), `'assigned'` (15). SPEC uses `'all'`.
- `public.user_roles(user_id text NOT NULL, role_id uuid NOT NULL)`: `user_id` is `text` (matches `users.id::text`).
- `public.user_permission_overrides(user_id uuid, company_id uuid NOT NULL, permission text, scope text, granted boolean DEFAULT true)`: **`company_id` is NOT NULL** — every SPEC operator override row carries `company_id = OPS_OPERATIONS_COMPANY_ID` by convention. `expires_at` does NOT exist; SPEC does not reference it.
- `public.notifications.user_id` is `text`, `public.notifications.company_id` is `text NOT NULL`. The table is actively used in production (291 rows at audit time; 16 distinct `type` values in the last 30 days; consumed by `ops-web/src/components/layouts/notifications-drawer.tsx` mounted in `dashboard-layout.tsx`). The `SPEC-NOTIFICATION-RAIL-DEPRECATED` flag was a false alarm — the rail is alive as an edge-tab drawer (see 07_ROLLOUT.md § Gate resolutions).
- `public.roles(id uuid NOT NULL, name text NOT NULL, hierarchy int NOT NULL, is_preset boolean NOT NULL, company_id uuid, ...)`: SPEC Operator role seed must populate `name`, `hierarchy`, `is_preset`, and may leave `company_id` null (the SPEC role is global, not customer-scoped). Existing preset roles use UUIDs `00000000-0000-0000-0000-000000000001..6`; SPEC Operator uses `00000000-0000-0000-0000-0000000000a1` to clearly separate the SPEC namespace.
- `private` schema already exists, owned by `postgres`. Existing OPS convention places SECURITY DEFINER functions (used by RLS) in `private`: `private.current_user_has_permission`, `private.resolve_uid`, `private.current_user_is_admin`, `private.get_user_company_id`, etc. SPEC follows this pattern.
- `pg_cron` extension installed (v1.6.4); `cron.schedule(name, schedule, query)` lives in the `cron` schema. `citext` is not yet installed; `create extension if not exists citext` is idempotent.

17 new tables (16 SPEC engagement tables + 1 public board snapshot table) + 1 dedicated operator-gate function. No extensions to `companies` at launch.

Revised 2026-05-25 (third pass) to:

- Add `private.is_spec_operator()` and route every admin RLS policy and admin route through it (CR-1).
- Make `spec_projects.tos_version_accepted` / `tos_accepted_at` nullable + add a CHECK constraint that requires them once the row leaves the pre-deposit states (CR-2).
- Replace the broken `spec_board_counts` view with a `spec_public_board_snapshot` TABLE refreshed every 5 min by a `SECURITY DEFINER` function via `pg_cron`, plus a manual force-refresh from `/admin/spec` (CR-3).
- Add `spec_refund_requests.refund_breakdown` jsonb to record per-milestone refund actions (refund / void / credit_note / mark_uncollectible) and extend `spec_payment_status` with `voided`, `partially_refunded`, `uncollectible` (CR-4).
- Add `owner_purchase_approved` to `spec_acceptance_events.event_type` so Path B captures BOTH the buyer's ToS acceptance at Stripe checkout AND the account_holder's purchase approval as binding acceptance events (CR-5).
- Add `spec_projects.billing_province` collected pre-Stripe; server-side Quebec rejection happens before any Stripe payment session is created (CR-6).
- Default `spec_module_entitlements.enabled` to `false`; flipped to `true` only at the delivery walkthrough (CR-7).
- Reconcile queue-count semantics: queue = `awaiting_deposit` + `deposit_paid` everywhere (MJ-1).
- Document the Supabase Storage bucket policy for intake uploads (MJ-2).
- Note the migration must generate a CONCRETE RLS policy per long-tail table — no placeholder comments (MJ-6).
- Seed an internal "OPS Operations" company so operator-facing notifications and no-company-buyer notifications have a valid `company_id` (MJ-7).
- Hash approval and buyer-checkout tokens at rest; the URL emits the plaintext, the DB stores only the hash (MN-4).
- Make `spec_blocked_buyers.email` use `citext` for case-insensitive uniqueness (MN-5).
- Drop the denormalized `ytd_referrer_payout_cents` column; the YTD figure is derived (MN-6).
- Add `is_test boolean not null default false` to every SPEC engagement table (MJ-10).
- Add fourth-pass bug_reports: `SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION`, `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA`, `SPEC-LIVE-SCHEMA-MISMATCHES`, and `SPEC-NO-COMPANY-BUYER-FLOW-LOCK` (all resolved 2026-05-25 — see 07_ROLLOUT.md § Gate resolutions).

Revised 2026-07-14 (**Tier Model v2** — applied to prod; see [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md) § 6, the implementation contract):

- **Tier slugs are now `spec01` / `spec02` / `spec03`.** `spec_capacity` re-seeded per 10 § 2 (prices 200000/750000/2500000 — spec03 is the FLOOR; retainer cents 0/39500/75000; slots 6/3/1; support 30/60/90; discovery 2-4/5-10/10-15; build 3-7/15-25/30-60). Tier CHECK constraints on `spec_capacity` + `spec_projects` retargeted to the v2 slugs only (`spec_projects` was 0 rows — re-seed, not a data migration). The `spec_capacity` seed block below (§ Core tables) documents the v1 shape; the live seed is `migrations/20260715035835_spec_tier_model_v2_reseed.sql`.
- `subscription_multiplier_estimate` retired from all published surfaces (column remains NOT NULL, seeded `0`, unread). `polish_hours_budget` is an unpublished internal budget; v1 ladder (2/4/8) carried.
- **New `spec_projects` columns** (`migrations/20260715035945_spec_projects_v2_columns.sql`, additive/nullable): `locked_total_cents` (SPEC-03 total locked at scope sign-off; null = floor pricing), `white_label` (boolean not null default false), `care_monthly_cents` (copied from capacity at insert + white-label bump; null = no care plan), `care_started_at` (stamped when the support window ends and care billing starts).

## Status enum

```sql
create type spec_project_status as enum (
  'awaiting_owner_approval',  -- buyer ≠ account_holder, approval requested, Stripe NOT yet charged
  'awaiting_deposit',         -- approval granted (or Path A pre-Stripe-redirect), short-lived checkout token issued
  'deposit_paid',             -- P1 paid, awaiting intake completion + discovery scheduling
  'discovery',                -- in discovery sessions; sub-states via timestamps
  'building',                 -- scope signed (P2 fired); active build; sub-states via timestamps
  'on_hold',                  -- paused; hold_type distinguishes customer_requested vs ops_blocked
  'stalled_on_hold',          -- paused beyond 90d with no action (customer_requested only)
  'support',                  -- P4 delivered, in support window
  'on_retainer',              -- support ended, paying retainer
  'completed',                -- support / retainer ended cleanly
  'stalled',                  -- no contact at deposit_paid or discovery stage; emails stopped after 90d
  'cancelled',                -- terminated pre-delivery
  'refunded'                  -- refund issued
);

create type spec_hold_type as enum (
  'customer_requested',  -- frees the slot, customer rejoins queue on resume
  'ops_blocked'          -- consumes the slot, waiting on customer input/integration
);
```

Sub-states ("scope signed", "midpoint accepted") are tracked by presence/absence of timestamps on `spec_projects` and by rows in `spec_acceptance_events`. The enum stays manageable.

## Operator gate — `private.is_spec_operator()`

`public.has_permission()` is unsafe as a SPEC admin gate because it returns true for any customer-company admin (it short-circuits through `is_company_admin`, `account_holder_id`, and `admin_ids` before consulting `role_permissions`). SPEC defines its own dedicated check that only consults `role_permissions` / `user_permission_overrides` and never trusts customer-company admin status.

`SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA` resolved 2026-05-25 (see 07_ROLLOUT.md § Gate resolutions): the function lives in the `private` schema, matching the existing OPS convention (`private.current_user_has_permission`, `private.resolve_uid`, `private.current_user_is_admin`). `private` schema is owned by `postgres`, has `USAGE` granted to `authenticated`, and no `USAGE` to `anon`. The function gets `EXECUTE` granted to `public` — which resolves to "anything with USAGE on `private`" — i.e., authenticated only, never anon.

```sql
-- Migration: YYYYMMDD_spec_phase1_operator_gate.sql
create schema if not exists private;  -- idempotent; live DB already has it

create or replace function private.is_spec_operator()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.role_permissions rp
    join public.user_roles ur on ur.role_id = rp.role_id
    where ur.user_id = public.get_user_id()
      and rp.permission = 'spec.admin'
      and rp.scope = 'all'
  )
  or exists (
    select 1
    from public.user_permission_overrides upo
    where upo.user_id::text = public.get_user_id()
      and upo.permission = 'spec.admin'
      and upo.granted = true
      -- company_id is NOT NULL on the table. SPEC overrides are inserted with
      -- company_id = OPS_OPERATIONS_COMPANY_ID by convention. No filter needed
      -- here — the convention is enforced at insert time.
  );
$$;

-- Grant pattern matches existing private.* functions (verified live 2026-05-25):
--   private schema USAGE → authenticated (already granted, idempotent here)
--   private schema USAGE → service_role (new — needed for server-route calls)
--   function EXECUTE → public (resolves to authenticated, since anon lacks USAGE)
grant usage on schema private to authenticated, service_role;
grant execute on function private.is_spec_operator() to public;
```

`role_permissions.scope` accepts `'all'` in production (canonical value, 280 rows). The Phase 1 migration verifies this. If a future migration adds `'global'` (or any other broader scope), the `is_spec_operator()` body is updated in the same migration. Until then, only `'all'` is consulted.

**Required role + permission seed** (resolved per `SPEC-LIVE-SCHEMA-MISMATCHES`):

```sql
-- Dedicated SPEC Operator role (global, not customer-scoped).
-- Uses the 'a1' tail to keep separate from existing preset roles (..01..06).
insert into public.roles (id, name, hierarchy, is_preset, company_id, created_at)
values (
  '00000000-0000-0000-0000-0000000000a1',
  'SPEC Operator',
  0,                                          -- highest precedence
  true,                                        -- preset, not customer-created
  null,                                        -- global, not company-scoped
  now()
)
on conflict (id) do nothing;

-- Grant the SPEC admin permission to the SPEC Operator role.
insert into public.role_permissions (id, role_id, permission, scope, created_at)
values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a1',
  'spec.admin',
  'all',
  now()
)
on conflict do nothing;

-- Add Jackson (the founder + initial SPEC operator) to the role.
-- The migration substitutes <JACKSON_USER_ID> from an env-supplied config or
-- from a one-shot lookup against a known email at migration time.
insert into public.user_roles (id, user_id, role_id, created_at)
values (
  gen_random_uuid(),
  '<JACKSON_USER_ID>',
  '00000000-0000-0000-0000-0000000000a1',
  now()
)
on conflict do nothing;
```

**Future delegated SPEC operators** are granted via `user_permission_overrides`:

```sql
insert into public.user_permission_overrides
  (id, user_id, company_id, permission, scope, granted, created_at, updated_at)
values (
  gen_random_uuid(),
  '<DELEGATED_OPERATOR_USER_ID>',
  '00000000-0000-0000-0000-00000000000a',     -- OPS_OPERATIONS_COMPANY_ID
  'spec.admin',
  'all',
  true,
  now(),
  now()
)
on conflict do nothing;
```

Every admin RLS policy and every admin server-side route uses `private.is_spec_operator()`. The legacy generic `has_permission(...)` check is NOT used anywhere in SPEC. Customer-company admins do not satisfy the SPEC operator gate.

## OPS Operations internal company

SPEC operator-facing events require a valid `company_id` because `public.notifications.company_id` is `text NOT NULL` in the production schema. Per resolved `SPEC-NOTIFICATION-RAIL-DEPRECATED` (2026-05-25), the notification rail is active and consumed by `ops-web/src/components/layouts/notifications-drawer.tsx` mounted in `dashboard-layout.tsx` — SPEC writes directly to `public.notifications` for all operator events. Per resolved `SPEC-NO-COMPANY-BUYER-FLOW-LOCK` (2026-05-25), no-company buyer notifications are eliminated because the deposit gate enforces `users.company_id IS NOT NULL` before a `spec_projects` row can be inserted; customer-facing notifications always carry `company_id = linked_company_id`.

The Phase 1 migration seeds a single internal "OPS Operations" company row with a known UUID exported to application code as the `OPS_OPERATIONS_COMPANY_ID` constant (`00000000-0000-0000-0000-00000000000a`). Jackson's user is a member, and all SPEC operators are added as members. Operator-facing SPEC notifications use this `company_id` when writing to `public.notifications`. The `is_test = false` filter on the public board snapshot is unaffected.

```sql
-- Seed (migration-managed). `companies.slug` is not assumed; live schema has no slug.
insert into public.companies (id, name, created_at)
values (
  '00000000-0000-0000-0000-00000000000a',
  'OPS Operations',
  now()
)
on conflict (id) do nothing;
-- Application code reads the constant OPS_OPERATIONS_COMPANY_ID; never hard-codes.
```

## Core tables

Every SPEC engagement table below carries `is_test boolean not null default false` (MJ-10). Default `false`. Admin queries default-filter `is_test = false`. The `/admin/spec` UI has a "Test mode" toggle that includes test rows. This is reproduced in every table definition below — not abbreviated — so the migration is a direct paste.

```sql
-- ─── 1. Tier-level capacity + estimates ─────────────────────────────────
create table public.spec_capacity (
  tier text primary key check (tier in ('setup', 'build', 'enterprise')),
  -- Capacity
  slot_ceiling int not null,
  manual_next_start_override date,
  is_accepting_bookings boolean not null default true,
  public_note text,
  -- Duration estimates
  discovery_days_min int not null,
  discovery_days_max int not null,
  build_days_min int not null,
  build_days_max int not null,
  support_window_days int not null,    -- 30 / 60 / 90
  -- Pricing
  total_price_cents int not null,      -- 300000 / 850000 / 1800000
  -- Subscription premium estimate (published on /spec)
  subscription_multiplier_estimate numeric(4,2) not null,  -- 0.15 / 0.30 / 0.50
  -- Retainer
  retainer_monthly_cents int not null, -- 25000 / 45000 / 75000
  -- Polish budget
  polish_hours_budget numeric(4,2) not null,  -- 2 / 4 / 8
  -- Ops
  admin_notes text,
  updated_at timestamptz default now()
);
-- spec_capacity is configuration, not engagement data. No is_test column.

insert into public.spec_capacity values
  ('setup',      4, null, true, null, 3,  5,  7,  14, 30,  300000, 0.15, 25000, 2, null, now()),
  ('build',      3, null, true, null, 5,  7,  14, 21, 60,  850000, 0.30, 45000, 4, null, now()),
  ('enterprise', 1, null, true, null, 7,  14, 28, 42, 90, 1800000, 0.50, 75000, 8, null, now());

-- ─── 2. Main project records ─────────────────────────────────────────────
create table public.spec_projects (
  id uuid primary key default gen_random_uuid(),

  -- Identity
  tier text not null check (tier in ('setup','build','enterprise')),
  original_tier text,
  status spec_project_status not null,
  buyer_user_id uuid not null references public.users(id) on delete restrict,
  account_holder_user_id uuid references public.users(id) on delete set null,  -- snapshot at deposit; may differ from current account_holder later
  linked_company_id uuid references public.companies(id) on delete set null,
  customer_email text not null,
  customer_name text,
  customer_phone text,
  customer_gst_number text,

  -- Billing address (collected pre-Stripe so Quebec rejection happens before Stripe payment)
  billing_address_line1 text,
  billing_address_line2 text,
  billing_city text,
  billing_province text,                -- ISO-3166-2 subdivision code, e.g. 'BC', 'ON', 'QC'
  billing_postal_code text,
  billing_country text default 'CA',
  quebec_eligibility_attested_at timestamptz,
  quebec_eligibility_payload jsonb,      -- no QC head office, operating address, establishment, or material SPEC use

  -- Stripe
  stripe_customer_id text,
  stripe_session_id text unique,

  -- ToS acceptance — populated by the approved Stripe payment success webhook.
  -- Nullable so the row can exist in awaiting_owner_approval / awaiting_deposit before any
  -- ToS event has been recorded. The CHECK constraint enforces presence once the row leaves
  -- the pre-deposit states. The values mirror the authoritative spec_acceptance_events row.
  tos_version_accepted text,
  tos_accepted_at timestamptz,
  tos_accepted_ip text,

  -- Attribution
  referrer_email text,
  attribution jsonb,  -- {utm_source, utm_medium, utm_campaign, utm_content, utm_term, gclid, fbclid, landing_url, first_touch_at}

  -- Lifecycle timestamps
  owner_approval_requested_at timestamptz,
  owner_approved_at timestamptz,
  owner_declined_at timestamptz,
  checkout_token_issued_at timestamptz,
  checkout_token_expires_at timestamptz,
  deposit_paid_at timestamptz,
  intake_sent_at timestamptz,
  intake_completed_at timestamptz,
  company_provisioned_at timestamptz,
  discovery_scheduled_at timestamptz,
  discovery_started_at timestamptz,
  scope_doc_drafted_at timestamptz,
  scope_doc_sent_at timestamptz,
  scope_doc_signed_at timestamptz,
  build_started_at timestamptz,
  midpoint_demo_at timestamptz,
  midpoint_accepted_at timestamptz,
  walkthrough_completed_at timestamptz,         -- CANONICAL ANCHOR for guarantee + support + referral + retainer offer
  walkthrough_recording_url text,
  support_window_ends_at timestamptz,
  retainer_started_at timestamptz,
  completed_at timestamptz,

  -- Hold state
  on_hold_at timestamptz,
  on_hold_reason text,
  hold_type spec_hold_type,
  prior_status spec_project_status,
  on_hold_expires_at timestamptz,
  resume_requested_at timestamptz,
  resumed_at timestamptz,

  stalled_at timestamptz,
  stalled_reason text,
  cancelled_at timestamptz,
  cancellation_reason text,
  refunded_at timestamptz,
  forfeit_at timestamptz,
  tier_upgraded_at timestamptz,

  -- Operational
  estimated_completion_date date,
  scope_doc_url text,
  intake_responses jsonb,
  notes text,
  last_communication_at timestamptz,
  no_show_count int default 0,

  -- Subscription terms locked at P2
  locked_subscription_multiplier numeric(4,2),
  locked_module_surcharge_cents int default 0,
  subscription_locked_at timestamptz,
  subscription_first_bill_at date,
  subscription_renegotiate_at date,

  -- Polish budget
  polish_hours_budget numeric(4,2),
  polish_hours_used numeric(4,2) default 0,

  -- Test mode (MJ-10)
  is_test boolean not null default false,

  -- Meta
  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  -- CR-2: ToS evidence must exist as soon as the row represents a paid or in-progress engagement.
  -- Nullable in pre-deposit states (awaiting_owner_approval, awaiting_deposit), required everywhere else.
  constraint spec_projects_tos_required_after_deposit
    check (
      status in ('awaiting_owner_approval', 'awaiting_deposit')
      or (tos_version_accepted is not null and tos_accepted_at is not null)
    ),

  -- CR-6 + fourth pass: a Canadian engagement must have a province on file before deposit_paid.
  -- Quebec ('QC') is rejected at the API layer pre-Stripe; additional Quebec head-office /
  -- operating-address / establishment / material-use attestations are enforced by the server route.
  constraint spec_projects_province_required_after_deposit
    check (
      status in ('awaiting_owner_approval', 'awaiting_deposit')
      or billing_province is not null
    ),

  constraint spec_projects_no_quebec
    check (billing_province is null or billing_province <> 'QC')
);

create index spec_projects_status_tier_idx
  on public.spec_projects (status, tier)
  where status in ('deposit_paid','discovery','building','on_hold');

create index spec_projects_estimated_completion_idx
  on public.spec_projects (tier, estimated_completion_date)
  where status in ('discovery','building','on_hold');

create index spec_projects_buyer_idx on public.spec_projects (buyer_user_id);
create index spec_projects_account_holder_idx on public.spec_projects (account_holder_user_id);
create index spec_projects_company_idx on public.spec_projects (linked_company_id);
create index spec_projects_hold_idx on public.spec_projects (hold_type) where status = 'on_hold';
create index spec_projects_is_test_idx on public.spec_projects (is_test) where is_test = true;

-- ─── 3. Owner approval requests (gates Stripe payment for buyer ≠ owner) ─
create type spec_owner_approval_status as enum ('pending','approved','declined','expired');

create table public.spec_owner_approval_requests (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  buyer_user_id uuid not null references public.users(id) on delete restrict,
  account_holder_user_id uuid not null references public.users(id) on delete restrict,
  linked_company_id uuid not null references public.companies(id) on delete restrict,
  tier text not null,
  approved_total_cents int not null,    -- total tier price snapshot at approval time
  approved_deposit_cents int not null,  -- P1 amount snapshot at approval time
  approved_tos_version_hash text,       -- the ToS version hash the account_holder reviewed when approving
  status spec_owner_approval_status not null default 'pending',

  -- Tokens are stored as bcrypt/argon2 hashes only. The plaintext is emitted in URLs once,
  -- never re-readable from the DB. The API hashes the inbound URL token and compares.
  approval_token_hash text unique,
  buyer_checkout_token_hash text unique,
  buyer_checkout_expires_at timestamptz,

  requested_at timestamptz default now(),
  decided_at timestamptz,
  decided_ip text,
  decided_user_agent text,
  is_test boolean not null default false
);

create index spec_owner_approval_token_idx on public.spec_owner_approval_requests (approval_token_hash);
create index spec_owner_approval_buyer_token_idx on public.spec_owner_approval_requests (buyer_checkout_token_hash);

-- ─── 4. Versioned scope documents (the SOW) ──────────────────────────────
create table public.spec_scope_documents (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  version int not null,
  content_hash text not null,                -- sha256 of content_json
  content_json jsonb not null,               -- feature list, acceptance criteria, exclusions, midpoint def, delivery def, subscription terms, surcharge
  external_url text,                         -- optional Notion/Google Doc link
  drafted_at timestamptz not null default now(),
  sent_at timestamptz,
  superseded_at timestamptz,
  is_test boolean not null default false,
  unique (spec_project_id, version)
);

create index spec_scope_documents_project_idx
  on public.spec_scope_documents (spec_project_id, version desc);

-- ─── 5. Acceptance events (legal evidence chain) ─────────────────────────
create table public.spec_acceptance_events (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  scope_document_id uuid references public.spec_scope_documents(id) on delete set null,
  event_type text not null check (event_type in (
    'tos_accepted',
    'owner_purchase_approved',
    'scope_signoff',
    'midpoint_accepted',
    'delivery_accepted',
    'change_order_accepted'
  )),
  accepted_by_user_id uuid not null references public.users(id) on delete restrict,
  accepted_at timestamptz not null default now(),
  accepted_ip text,
  accepted_user_agent text,
  signature_method text check (signature_method in ('click_in_app','docusign','email_reply')),
  signature_evidence_url text,
  payload_hash text,  -- hash of exactly what they saw at acceptance time
  is_test boolean not null default false
);

create index spec_acceptance_events_project_idx
  on public.spec_acceptance_events (spec_project_id, accepted_at);
create index spec_acceptance_events_type_idx
  on public.spec_acceptance_events (event_type, spec_project_id);

-- ─── 6. Module entitlements (replaces companies.spec_* booleans) ─────────
create table public.spec_module_entitlements (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  module_key text not null,
  -- CR-7: default disabled. The row is reserved at scope sign-off (to lock multiplier + surcharge)
  -- but does not grant access. Delivery walkthrough flips enabled = true; refund / dispute /
  -- non-payment / subscription-lapse flip it back to false.
  enabled boolean not null default false,
  disabled_reason text check (disabled_reason in (
    'non_payment','dispute','refunded','subscription_lapse',
    'customer_request','ops_decision','not_yet_delivered'
  )),
  stripe_subscription_item_id text,
  multiplier numeric(4,2) not null,
  surcharge_cents int default 0,
  entitled_at timestamptz default now(),
  enabled_at timestamptz,     -- stamped when enabled flips false → true (delivery walkthrough)
  disabled_at timestamptz,
  updated_at timestamptz default now(),
  is_test boolean not null default false,
  unique (spec_project_id, module_key)
);

create index spec_module_entitlements_company_idx
  on public.spec_module_entitlements (company_id) where enabled = true;

-- ─── 7. Payment milestones ───────────────────────────────────────────────
create type spec_payment_milestone as enum ('deposit','scope_signoff','midpoint','delivery');
-- CR-4: extended enum to support every state a milestone can land in during refund.
create type spec_payment_status as enum (
  'pending',
  'invoiced',
  'paid',
  'overdue',
  'disputed',
  'refunded',
  'partially_refunded',
  'voided',
  'uncollectible'
);

create table public.spec_payments (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  milestone spec_payment_milestone not null,
  stripe_payment_intent_id text,
  stripe_invoice_id text,
  amount_cents int not null,
  tax_cents int default 0,
  total_cents int not null,
  status spec_payment_status not null default 'pending',
  due_date date,
  invoiced_at timestamptz,
  paid_at timestamptz,
  overdue_at timestamptz,
  refunded_at timestamptz,
  voided_at timestamptz,
  marked_uncollectible_at timestamptz,
  amount_refunded_cents int default 0,
  credit_note_stripe_id text,           -- Stripe credit note ID when status = partially_refunded
  created_at timestamptz default now(),
  is_test boolean not null default false
);

create unique index spec_payments_project_milestone_idx
  on public.spec_payments (spec_project_id, milestone);

-- ─── 8. Change orders ────────────────────────────────────────────────────
create type spec_change_order_type as enum (
  'minor_hourly','major_fixed','polish_budget','platform_compat_rebuild','tier_upgrade'
);
create type spec_change_order_status as enum (
  'proposed','customer_approved','customer_declined','in_progress','completed','paid'
);

create table public.spec_change_orders (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  title text not null,
  description text not null,
  change_type spec_change_order_type not null,
  estimated_hours numeric(5,2),
  hourly_rate_cents int default 22500,
  fixed_price_cents int,
  delivery_impact_days int default 0,
  status spec_change_order_status not null default 'proposed',
  acceptance_event_id uuid references public.spec_acceptance_events(id),  -- the customer's accept record
  stripe_invoice_id text,
  final_cost_cents int,
  proposed_at timestamptz default now(),
  approved_at timestamptz,
  declined_at timestamptz,
  completed_at timestamptz,
  invoiced_at timestamptz,
  paid_at timestamptz,
  is_test boolean not null default false
);

-- ─── 9. Feature acceptance criteria ──────────────────────────────────────
create type spec_feature_status as enum ('pending','passing','failing');

create table public.spec_feature_acceptance (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  scope_document_id uuid not null references public.spec_scope_documents(id) on delete cascade,
  feature_name text not null,
  acceptance_criteria text not null,
  status spec_feature_status not null default 'pending',
  verified_at timestamptz,
  verified_by_user_id uuid references public.users(id) on delete set null,
  failure_notes text,
  is_test boolean not null default false
);

-- ─── 10. Satisfaction ratings ────────────────────────────────────────────
create table public.spec_satisfaction_ratings (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  milestone text not null check (milestone in ('midpoint','delivery')),
  feature_name text not null,
  rating int not null check (rating between 1 and 5),
  notes text,
  submitted_at timestamptz default now(),
  is_test boolean not null default false
);

-- ─── 11. Support tickets (covers support, retainer, and ad-hoc phases) ───
create type spec_ticket_severity as enum ('critical','high','cosmetic_enhancement');
create type spec_ticket_status as enum ('open','in_progress','resolved','escalated_to_change_order');
create type spec_ticket_phase as enum ('support','retainer','ad_hoc');

create table public.spec_support_tickets (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  phase spec_ticket_phase not null default 'support',
  title text not null,
  description text not null,
  severity spec_ticket_severity not null,
  customer_classification spec_ticket_severity,
  is_in_scope boolean,
  status spec_ticket_status not null default 'open',
  linked_change_order_id uuid references public.spec_change_orders(id) on delete set null,
  opened_at timestamptz default now(),
  responded_at timestamptz,
  resolved_at timestamptz,
  is_test boolean not null default false
);

create index spec_support_tickets_project_idx
  on public.spec_support_tickets (spec_project_id, opened_at desc);

-- ─── 12. Retainers ───────────────────────────────────────────────────────
create type spec_retainer_status as enum ('active','paused','cancelled');

create table public.spec_retainers (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  stripe_subscription_id text unique not null,
  monthly_amount_cents int not null,
  status spec_retainer_status not null default 'active',
  started_at timestamptz not null,
  paused_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  updated_at timestamptz default now(),
  is_test boolean not null default false
);

-- ─── 13. Communications log ──────────────────────────────────────────────
create table public.spec_communications (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  direction text not null check (direction in ('outbound','inbound')),
  channel text not null check (channel in ('email','admin_note','call_log','video_message','system')),
  summary text not null,
  body text,
  occurred_at timestamptz default now(),
  logged_by_user_id uuid references public.users(id) on delete set null,
  is_test boolean not null default false
);

create index spec_communications_project_idx
  on public.spec_communications (spec_project_id, occurred_at desc);

-- ─── 14. Refund requests ─────────────────────────────────────────────────
create type spec_refund_status as enum ('pending','processed','partial','failed','denied');
create type spec_refund_source as enum ('customer_initiated','stripe_dispute');

create table public.spec_refund_requests (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  request_source spec_refund_source not null,
  customer_reason_text text,
  requested_at timestamptz default now(),
  processed_at timestamptz,
  processed_by_user_id uuid references public.users(id) on delete set null,
  -- CR-4: per-milestone breakdown of what action was taken.
  -- Shape:
  -- [
  --   {
  --     "milestone": "deposit" | "scope_signoff" | "midpoint" | "delivery",
  --     "stripe_resource_id": "pi_..." | "in_...",
  --     "action": "refund" | "void" | "credit_note" | "mark_uncollectible",
  --     "amount_cents": 75000,
  --     "status": "succeeded" | "failed",
  --     "executed_at": "ISO-8601",
  --     "error": null | "..."
  --   },
  --   ...
  -- ]
  refund_breakdown jsonb,
  -- Optional legacy convenience column for "total cash actually refunded across all paid milestones".
  -- Equals sum of action='refund' or action='credit_note' amounts in refund_breakdown.
  total_refund_cents int,
  -- Optional legacy convenience column for Stripe refund IDs (subset of refund_breakdown).
  stripe_refund_ids jsonb,
  is_goodwill boolean default false,
  is_guarantee_invocation boolean default false,  -- true = 30-day soft guarantee
  status spec_refund_status not null default 'pending',
  is_test boolean not null default false
);

-- One soft-guarantee invocation per engagement (enforced).
create unique index spec_refund_one_guarantee_per_project_idx
  on public.spec_refund_requests (spec_project_id)
  where is_guarantee_invocation = true and status in ('pending','processed','partial');

-- ─── 15. Referrals ───────────────────────────────────────────────────────
create type spec_referral_status as enum (
  'pending','eligible','kyc_required','review','paid','forfeited','held'
);

create table public.spec_referrals (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  referrer_name text,
  referrer_email text not null,
  referrer_stripe_account_id text,
  bounty_cents int default 50000,
  status spec_referral_status not null default 'pending',
  self_referral_flag boolean default false,
  related_entity_flag boolean default false,
  related_entity_notes text,
  -- ytd_referrer_payout_cents removed (MN-6) — derived from sum() at query time.
  t4a_required boolean default false,
  eligible_at timestamptz,
  paid_at timestamptz,
  forfeited_at timestamptz,
  held_reason text,
  stripe_transfer_id text,
  is_test boolean not null default false
);

create index spec_referrals_referrer_email_idx
  on public.spec_referrals (referrer_email, status, paid_at);
-- /admin/spec/referrals derives YTD via:
--   select sum(bounty_cents)
--   from spec_referrals
--   where referrer_email = $1
--     and status = 'paid'
--     and paid_at >= date_trunc('year', now())
--     and is_test = false;

-- ─── 16. Blocked buyers ──────────────────────────────────────────────────
-- citext extension required (MN-5)
create extension if not exists citext;

create table public.spec_blocked_buyers (
  id uuid primary key default gen_random_uuid(),
  email citext not null,
  stripe_customer_id text,
  blocked_at timestamptz default now(),
  blocked_reason text not null,
  blocked_by_user_id uuid references public.users(id) on delete set null,
  unblocked_at timestamptz
);
-- spec_blocked_buyers is operator-only data, not engagement data. No is_test column.

create unique index spec_blocked_buyers_email_idx
  on public.spec_blocked_buyers (email) where unblocked_at is null;
```

## Public board — snapshot table (replaces the broken view)

The previous spec proposed a `spec_board_counts` view with `security_invoker = on` granted to anon. That cannot work: with invoker rights, the view runs against `spec_projects` whose RLS blocks anon — the view returns empty or errors. Loosening `spec_projects` RLS to allow anon SELECT (even of a derived shape) leaks pipeline state.

**Locked answer:** replace the view with a TABLE that is refreshed every 5 minutes by a `SECURITY DEFINER` function via `pg_cron`. Anon SELECT is granted on the table (which holds only the sanitized aggregate, never raw project rows). A manual force-refresh button in `/admin/spec` calls the same function via a server route. The Vercel route serving the board read sets `Cache-Control: public, max-age=300, s-maxage=300` so most reads land on the edge cache and never hit Supabase.

```sql
-- Single-row table holding the public board snapshot.
create table public.spec_public_board_snapshot (
  id boolean primary key default true check (id = true),  -- ensures exactly one row
  data jsonb not null,                                    -- shape documented below
  refreshed_at timestamptz not null default now()
);

-- Initial seed row (empty array; the cron will populate it on first run).
insert into public.spec_public_board_snapshot (id, data, refreshed_at)
values (true, '[]'::jsonb, now())
on conflict (id) do nothing;

grant select on public.spec_public_board_snapshot to anon, authenticated;

-- Refresh function — SECURITY DEFINER so it can read spec_projects regardless of RLS,
-- runs as the table owner. Returns nothing; just rewrites the snapshot row.
-- Lives in the `private` schema per resolved SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA.
create or replace function private.refresh_spec_board_snapshot()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'tier', cap.tier,
    'availability',
      case
        when cap.is_accepting_bookings = false then 'CLOSED'
        when coalesce(active_ct, 0) < cap.slot_ceiling then 'OPEN'
        when coalesce(active_ct, 0) = cap.slot_ceiling
             and coalesce(queue_ct, 0) = 0 then 'LIMITED'
        else 'WAITLIST'
      end,
    'waitlist_bucket',
      case
        when coalesce(queue_ct, 0) = 0 then '0'
        when coalesce(queue_ct, 0) <= 2 then '1-2'
        else '3+'
      end,
    'next_start_week',
      case
        when cap.manual_next_start_override is not null
          then to_char(cap.manual_next_start_override, 'YYYY-IW')
        else to_char(
          coalesce(
            min_completion,
            current_date + (cap.discovery_days_max + cap.build_days_min) * interval '1 day'
          ),
          'YYYY-IW'
        )
      end,
    'is_accepting_bookings', cap.is_accepting_bookings,
    'public_note', cap.public_note
  ))
  into v_data
  from public.spec_capacity cap
  left join lateral (
    select
      -- Slot-consuming: discovery, building, ops_blocked hold (MJ-1, CR-3)
      count(*) filter (
        where p.status in ('discovery', 'building')
           or (p.status = 'on_hold' and p.hold_type = 'ops_blocked')
      ) as active_ct,
      -- Queue: awaiting_deposit + deposit_paid (locked: MJ-1)
      count(*) filter (
        where p.status in ('awaiting_deposit', 'deposit_paid')
      ) as queue_ct,
      -- Earliest projected completion among slot-consuming projects, used to seed next_start
      min(p.estimated_completion_date) filter (
        where p.status in ('discovery', 'building')
           or (p.status = 'on_hold' and p.hold_type = 'ops_blocked')
      ) as min_completion
    from public.spec_projects p
    where p.tier = cap.tier
      and p.is_test = false
  ) p on true;

  insert into public.spec_public_board_snapshot (id, data, refreshed_at)
  values (true, coalesce(v_data, '[]'::jsonb), now())
  on conflict (id) do update
    set data = excluded.data,
        refreshed_at = excluded.refreshed_at;
end;
$$;

-- service_role has USAGE on `private` (granted by the operator-gate migration)
-- and EXECUTE on the function. anon and authenticated do NOT get EXECUTE —
-- the manual force-refresh button is an operator-only server route that
-- gates on private.is_spec_operator() and uses the service-role client to call
-- private.refresh_spec_board_snapshot(). pg_cron runs as `postgres` which
-- owns the function — no grant needed for the scheduled run.
grant execute on function private.refresh_spec_board_snapshot() to service_role;

-- pg_cron schedule (extension already enabled on ops-app; cron.schedule lives in cron schema).
select cron.schedule(
  'spec_board_snapshot_refresh',
  '*/5 * * * *',
  $cron$ select private.refresh_spec_board_snapshot(); $cron$
);

-- Customer-facing read path:
--   /spec page → Server Component fetches /api/spec/board → reads spec_public_board_snapshot.
--   The /api/spec/board route emits Cache-Control: public, max-age=300, s-maxage=300, stale-while-revalidate=60.
--   The `refreshed_at` column is exposed in the response payload (MJ-4) so the UI can show
--   "UPDATED [N min ago]" and shift to amber after 72h staleness.
```

`spec_public_board_snapshot.data` shape (the JSON the anon read returns):

```jsonc
[
  {
    "tier": "setup",
    "availability": "OPEN",                  // CLOSED | OPEN | LIMITED | WAITLIST
    "waitlist_bucket": "0",                  // "0" | "1-2" | "3+"
    "next_start_week": "2026-23",            // ISO year-week of YYYY-IW
    "is_accepting_bookings": true,
    "public_note": null
  },
  { "tier": "build", "...": "..." },
  { "tier": "enterprise", "...": "..." }
]
```

A competitor or hostile actor reading the snapshot sees the availability bucket and a coarse waitlist range. They cannot infer exact occupancy, identities, or last-activity timestamps. `is_test = true` projects are excluded from the aggregation.

The legacy `spec_board_counts` view is NOT created. The `migrations/YYYYMMDD_spec_phase1_view_and_rls.sql` migration is renamed to `migrations/YYYYMMDD_spec_phase1_snapshot_and_rls.sql` to reflect this.

## Supabase Storage configuration (intake uploads)

Bucket name: `spec-intake`

Folder layout: `spec-intake/{spec_project_id}/{uploaded_filename}`

Bucket configuration (managed by the Phase 1 migration via the `storage.buckets` table + storage RLS):

- Public: `false`. All access is via signed URLs.
- File size limit: 25 MB per file.
- Allowed MIME types: `application/pdf`, `image/png`, `image/jpeg`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document` (docx), `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` (xlsx).
- Signed URL TTL: 24 hours (regenerated each time admin opens the file).
- Customer uploads should use a server route that verifies project membership and issues a narrow signed upload URL. Do not rely on broad raw Storage insert access for Phase 1.

Storage RLS (using `storage.objects` policies) for the Phase 1 conservative default:

```sql
-- Operators can read files directly. Customer reads use server-issued signed URLs.
create policy "spec-intake read operator only" on storage.objects
  for select using (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );

-- Operators can write directly. Customer uploads use a server route that verifies
-- project membership and issues a narrow signed upload URL.
create policy "spec-intake write operator only" on storage.objects
  for insert with check (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );

-- Deletion: operators only (no customer-driven deletes)
create policy "spec-intake delete operator only" on storage.objects
  for delete using (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );
```

Deletion policy: 90 days after the engagement reaches a terminal state (`completed`, `cancelled`, `refunded`). A weekly cron prunes objects whose parent project crossed the threshold. Customer can request earlier deletion via the data-export / off-boarding flow; OPS retains the right to keep files for the duration of any open dispute.

## Extensions to `companies`

The previous spec proposed `spec_subscription_active` and `spec_modules_enabled` booleans on `companies`. These cannot represent multi-engagement state and are removed. Module enablement is read from `spec_module_entitlements`.

No DDL changes to `companies` at launch. The iOS-sync additive-only constraint is satisfied because we are not adding, renaming, or dropping any `companies` columns at launch. The OPS Operations company row (seeded above) is just a regular row insert.

If iOS needs a fast boolean for "this company has any active SPEC module" without joining, add it via a generated column in a later migration (additive, nullable) once iOS clients have rolled forward. For Phase 1 launch, do not add it.

## RLS and server-route default

`SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION` is locked (see 07_ROLLOUT.md § Gate resolutions, 2026-05-25): customer-facing SPEC reads and writes use server routes with service-role access and return narrow projections. Raw SPEC tables are not exposed to customer clients in Phase 1, except for the intentionally public `spec_public_board_snapshot` read. Any later raw-table customer access requires a deliberate migration with strict grants, constraints, and verification.

**Phase 1 customer server-route surface (complete enumeration in 07_ROLLOUT.md):**
- `GET /api/spec/board` (public; reads `spec_public_board_snapshot` only)
- `POST /api/spec/create-checkout-session` (authenticated)
- `POST /api/spec/owner-approval/[token]` (authenticated; must match `account_holder_user_id`)
- `GET /api/spec/checkout/[buyer_checkout_token]` (authenticated; must match `buyer_user_id`)
- `POST /api/spec/intake/submit` (token-gated)
- `POST /api/account/spec/[id]/request-refund` (authenticated; must be buyer or account_holder)
- `POST /api/admin/spec/board/refresh` (operator-only)

**Phase 1 RLS posture: zero anon/authenticated client SDK access to raw SPEC tables, except `spec_public_board_snapshot` SELECT.** Every operator route additionally gates on `private.is_spec_operator()`. Customer routes use the service-role client + explicit `buyer_user_id || account_holder_user_id` authorization check + narrow projections returned to the caller.

Do not grant customer raw inserts into `spec_refund_requests`, `spec_support_tickets`, or `spec_satisfaction_ratings` unless the migration adds strict column-level grants, CHECK constraints, immutable server-computed fields, and tests proving customers cannot set operational fields. Phase 2 customer portal (`/account/spec/[id]`) continues the same server-route posture; it does NOT relax RLS.

```sql
alter table public.spec_capacity                  enable row level security;
alter table public.spec_projects                  enable row level security;
alter table public.spec_owner_approval_requests   enable row level security;
alter table public.spec_scope_documents           enable row level security;
alter table public.spec_acceptance_events         enable row level security;
alter table public.spec_module_entitlements       enable row level security;
alter table public.spec_payments                  enable row level security;
alter table public.spec_change_orders             enable row level security;
alter table public.spec_feature_acceptance        enable row level security;
alter table public.spec_satisfaction_ratings      enable row level security;
alter table public.spec_support_tickets           enable row level security;
alter table public.spec_retainers                 enable row level security;
alter table public.spec_communications            enable row level security;
alter table public.spec_refund_requests           enable row level security;
alter table public.spec_referrals                 enable row level security;
alter table public.spec_blocked_buyers            enable row level security;
alter table public.spec_public_board_snapshot     enable row level security;

-- Operator/service-role owned raw tables. Customer-facing reads and writes happen through server routes.
create policy "spec_capacity operator all" on public.spec_capacity
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_projects operator all" on public.spec_projects
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_owner_approval_requests operator all" on public.spec_owner_approval_requests
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_scope_documents operator all" on public.spec_scope_documents
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_acceptance_events operator all" on public.spec_acceptance_events
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_module_entitlements operator all" on public.spec_module_entitlements
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_payments operator all" on public.spec_payments
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_change_orders operator all" on public.spec_change_orders
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_feature_acceptance operator all" on public.spec_feature_acceptance
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_satisfaction_ratings operator all" on public.spec_satisfaction_ratings
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_support_tickets operator all" on public.spec_support_tickets
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_retainers operator all" on public.spec_retainers
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_communications operator all" on public.spec_communications
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_refund_requests operator all" on public.spec_refund_requests
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_referrals operator all" on public.spec_referrals
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_blocked_buyers operator all" on public.spec_blocked_buyers
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

-- Public board snapshot is intentionally exposed because it contains only sanitized aggregate data.
create policy "spec_public_board_snapshot public read" on public.spec_public_board_snapshot
  for select using (true);
create policy "spec_public_board_snapshot operator write" on public.spec_public_board_snapshot
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());
```

Service-role server routes bypass RLS and must enforce authorization in application code before returning any customer projection. The Phase 1 server-route surface is enumerated in 07_ROLLOUT.md § Gate resolutions → `SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION`. The minimal Phase 1 customer routes are:
- `POST /api/account/spec/[id]/request-refund` for Guarantee Refund / goodwill requests (only customer write surface in Phase 1).
- Read access to the customer's own project is deferred to the Phase 2 portal at `/account/spec/[id]`.

The migration handoff includes tests proving anon and authenticated customer clients cannot select or insert directly into raw SPEC operational tables, while server routes can perform the intended safe operations.

## Computed derivations (reference logic)

### Next-start date per tier (admin precise version)

```python
def next_start_date(tier):
    cap = spec_capacity[tier]
    if cap.manual_next_start_override:
        return cap.manual_next_start_override

    # Slot-consuming statuses: discovery, building, on_hold(hold_type='ops_blocked')
    consuming = projects.where(
        tier=tier,
        status__in=['discovery','building'],
        is_test=False,
    ) + projects.where(
        tier=tier,
        status='on_hold',
        hold_type='ops_blocked',
        is_test=False,
    )

    # Queue = awaiting_deposit + deposit_paid (locked: MJ-1)
    queue = projects.where(
        tier=tier,
        status__in=['awaiting_deposit','deposit_paid'],
        is_test=False,
    ).order_by('deposit_paid_at')

    if len(consuming) < cap.slot_ceiling and len(queue) == 0:
        return today() + business_days(3)

    slots = [p.estimated_completion_date for p in consuming]
    avg_build_days = (cap.build_days_min + cap.build_days_max) / 2
    for _ in range(len(queue)):
        next_slot = min(slots)
        slots.remove(next_slot)
        slots.append(next_slot + avg_build_days)

    return min(slots)
```

The public snapshot does NOT expose this exact date — only `next_start_week` (ISO year-week of YYYY-IW).

### Delivery window per tier

```python
def delivery_window(tier, next_start):
    cap = spec_capacity[tier]
    return (
        next_start + days(cap.build_days_min),
        next_start + days(cap.build_days_max)
    )
```

### Utilization for the admin capacity bar

```python
utilization = sum(active_count for tier in tiers) / sum(slot_ceiling for tier in tiers)
```

`active_count` here means slot-consuming projects per the next-start logic above (excluding `is_test = true`).

### YTD referral payout (derived; MN-6)

```sql
select coalesce(sum(bounty_cents), 0) as ytd_cents
from public.spec_referrals
where referrer_email = $1
  and status = 'paid'
  and paid_at >= date_trunc('year', now())
  and is_test = false;
```

Displayed in `/admin/spec/referrals`. Never denormalized.

## Migration notes

- iOS-sync constraint: only additive changes safe between iOS App Store releases. No `companies` columns are being added at launch (the previous spec's two booleans are removed before they ship). The new SPEC tables are all net-new — no iOS sync concern.
- Migrations split for clarity:
  - `migrations/YYYYMMDD_spec_phase1_enums_and_capacity.sql` — enums + `spec_capacity` seed + `citext` extension
  - `migrations/YYYYMMDD_spec_phase1_internal_company.sql` — OPS Operations company seed (constant UUID)
  - `migrations/YYYYMMDD_spec_phase1_operator_gate.sql` — `is_spec_operator()` function + grants
  - `migrations/YYYYMMDD_spec_phase1_core_tables.sql` — `spec_projects` (with billing_address + CHECK + is_test), `spec_owner_approval_requests` (token hashes + is_test), `spec_scope_documents`, `spec_acceptance_events` (incl. `owner_purchase_approved`), `spec_module_entitlements` (default disabled)
  - `migrations/YYYYMMDD_spec_phase1_money_tables.sql` — `spec_payments` (extended status enum), `spec_change_orders`, `spec_refund_requests` (refund_breakdown), `spec_referrals` (no YTD denorm), `spec_retainers`
  - `migrations/YYYYMMDD_spec_phase1_workflow_tables.sql` — `spec_feature_acceptance`, `spec_satisfaction_ratings`, `spec_support_tickets`, `spec_communications`, `spec_blocked_buyers` (citext)
  - `migrations/YYYYMMDD_spec_phase1_snapshot_and_rls.sql` — `spec_public_board_snapshot` + `refresh_spec_board_snapshot()` + pg_cron schedule + CONCRETE RLS policies per table (no placeholders) + grants
  - `migrations/YYYYMMDD_spec_phase1_storage.sql` — `spec-intake` Supabase Storage bucket + RLS + MIME + size limit
- The `spec.admin` permission seed: insert one row into `role_permissions` for the dedicated SPEC operator role (created in the migration if absent) with `permission='spec.admin', scope='all'`, then add Jackson's `user_id` to that role via `user_roles`. Customer-side company admins do NOT get this role. Future delegated SPEC operators are granted via `user_permission_overrides` with `permission='spec.admin', granted=true`.
- Phase 1 verification confirms `role_permissions.scope` accepts the literal value `'all'`. If a `'global'` value exists in production at migration time, the `is_spec_operator()` body is amended in the same migration to consult both. The currently-shipped revision uses only `'all'`.
- `SPEC-LIVE-SCHEMA-MISMATCHES` resolved 2026-05-25 (see 07_ROLLOUT.md § Gate resolutions): all schema assumptions verified live. New findings folded in here — `user_permission_overrides.company_id NOT NULL` requires `OPS_OPERATIONS_COMPANY_ID` on every SPEC override row; the `SPEC Operator` role seed must populate `name`, `hierarchy`, `is_preset`. `companies.slug` and `user_permission_overrides.expires_at` do not exist and are not referenced.
- `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA` resolved 2026-05-25 (see 07_ROLLOUT.md § Gate resolutions): both SECURITY DEFINER functions placed in the `private` schema, matching the existing OPS convention. Grants pattern verified against `private.current_user_has_permission` (EXECUTE → public; schema USAGE → authenticated; pg_cron runs as `postgres` with direct access).
