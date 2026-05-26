-- SPEC Phase 1 — Migration 4/8: Core engagement tables
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md § Core tables
-- Applied: 2026-05-25 via Supabase MCP apply_migration as `spec_phase1_core_tables`.
-- Every table carries is_test boolean default false (MJ-10).
-- spec_projects has CHECK constraints requiring tos + province after deposit (CR-2, CR-6).
-- spec_module_entitlements defaults enabled=false (CR-7).
-- spec_acceptance_events includes 'owner_purchase_approved' (CR-5).
-- spec_owner_approval_requests stores token HASHES not plaintext (MN-4).

-- ─── 2. spec_projects ─────────────────────────────────────────────────────
create table public.spec_projects (
  id uuid primary key default gen_random_uuid(),

  -- Identity
  tier text not null check (tier in ('setup', 'build', 'enterprise')),
  original_tier text,
  status spec_project_status not null,
  buyer_user_id uuid not null references public.users(id) on delete restrict,
  account_holder_user_id uuid references public.users(id) on delete set null,
  linked_company_id uuid references public.companies(id) on delete set null,
  customer_email text not null,
  customer_name text,
  customer_phone text,
  customer_gst_number text,

  -- Billing address (pre-Stripe Quebec block)
  billing_address_line1 text,
  billing_address_line2 text,
  billing_city text,
  billing_province text,
  billing_postal_code text,
  billing_country text default 'CA',
  quebec_eligibility_attested_at timestamptz,
  quebec_eligibility_payload jsonb,

  -- Stripe
  stripe_customer_id text,
  stripe_session_id text unique,

  -- ToS acceptance (populated by webhook on deposit_paid)
  tos_version_accepted text,
  tos_accepted_at timestamptz,
  tos_accepted_ip text,

  -- Attribution
  referrer_email text,
  attribution jsonb,

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
  walkthrough_completed_at timestamptz,
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

  -- Test mode
  is_test boolean not null default false,

  -- Meta
  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  -- CR-2: ToS evidence required once row leaves pre-deposit states
  constraint spec_projects_tos_required_after_deposit
    check (
      status in ('awaiting_owner_approval', 'awaiting_deposit')
      or (tos_version_accepted is not null and tos_accepted_at is not null)
    ),

  -- CR-6: Province required after deposit
  constraint spec_projects_province_required_after_deposit
    check (
      status in ('awaiting_owner_approval', 'awaiting_deposit')
      or billing_province is not null
    ),

  -- Quebec block
  constraint spec_projects_no_quebec
    check (billing_province is null or billing_province <> 'QC')
);

create index spec_projects_status_tier_idx
  on public.spec_projects (status, tier)
  where status in ('deposit_paid', 'discovery', 'building', 'on_hold');

create index spec_projects_estimated_completion_idx
  on public.spec_projects (tier, estimated_completion_date)
  where status in ('discovery', 'building', 'on_hold');

create index spec_projects_buyer_idx on public.spec_projects (buyer_user_id);
create index spec_projects_account_holder_idx on public.spec_projects (account_holder_user_id);
create index spec_projects_company_idx on public.spec_projects (linked_company_id);
create index spec_projects_hold_idx on public.spec_projects (hold_type) where status = 'on_hold';
create index spec_projects_is_test_idx on public.spec_projects (is_test) where is_test = true;

-- ─── 3. spec_owner_approval_requests ─────────────────────────────────────
create table public.spec_owner_approval_requests (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  buyer_user_id uuid not null references public.users(id) on delete restrict,
  account_holder_user_id uuid not null references public.users(id) on delete restrict,
  linked_company_id uuid not null references public.companies(id) on delete restrict,
  tier text not null,
  approved_total_cents int not null,
  approved_deposit_cents int not null,
  approved_tos_version_hash text,
  status spec_owner_approval_status not null default 'pending',

  -- Token HASHES only; plaintext is emitted in URLs once, never re-readable from DB.
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

-- ─── 4. spec_scope_documents ─────────────────────────────────────────────
create table public.spec_scope_documents (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  version int not null,
  content_hash text not null,
  content_json jsonb not null,
  external_url text,
  drafted_at timestamptz not null default now(),
  sent_at timestamptz,
  superseded_at timestamptz,
  is_test boolean not null default false,
  unique (spec_project_id, version)
);

create index spec_scope_documents_project_idx
  on public.spec_scope_documents (spec_project_id, version desc);

-- ─── 5. spec_acceptance_events ───────────────────────────────────────────
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
  signature_method text check (signature_method in ('click_in_app', 'docusign', 'email_reply')),
  signature_evidence_url text,
  payload_hash text,
  is_test boolean not null default false
);

create index spec_acceptance_events_project_idx
  on public.spec_acceptance_events (spec_project_id, accepted_at);
create index spec_acceptance_events_type_idx
  on public.spec_acceptance_events (event_type, spec_project_id);

-- ─── 6. spec_module_entitlements ─────────────────────────────────────────
create table public.spec_module_entitlements (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  module_key text not null,
  -- CR-7: default disabled; reserved at scope sign-off, enabled at delivery walkthrough.
  enabled boolean not null default false,
  disabled_reason text check (disabled_reason in (
    'non_payment', 'dispute', 'refunded', 'subscription_lapse',
    'customer_request', 'ops_decision', 'not_yet_delivered'
  )),
  stripe_subscription_item_id text,
  multiplier numeric(4,2) not null,
  surcharge_cents int default 0,
  entitled_at timestamptz default now(),
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_at timestamptz default now(),
  is_test boolean not null default false,
  unique (spec_project_id, module_key)
);

create index spec_module_entitlements_company_idx
  on public.spec_module_entitlements (company_id) where enabled = true;
