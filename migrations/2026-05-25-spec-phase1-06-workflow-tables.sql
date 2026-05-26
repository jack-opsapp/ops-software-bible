-- SPEC Phase 1 — Migration 6/8: Workflow tables (feature acceptance, satisfaction, tickets, comms, blocked)
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md
-- Applied: 2026-05-25 via Supabase MCP apply_migration as `spec_phase1_workflow_tables`.
-- MN-5: spec_blocked_buyers.email is citext for case-insensitive uniqueness.
-- spec_support_tickets phase enum covers support / retainer / ad_hoc (the retainer-tickets concept merged in).

-- ─── 9. spec_feature_acceptance ──────────────────────────────────────────
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

create index spec_feature_acceptance_project_idx
  on public.spec_feature_acceptance (spec_project_id, status);

-- ─── 10. spec_satisfaction_ratings ───────────────────────────────────────
create table public.spec_satisfaction_ratings (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  milestone text not null check (milestone in ('midpoint', 'delivery')),
  feature_name text not null,
  rating int not null check (rating between 1 and 5),
  notes text,
  submitted_at timestamptz default now(),
  is_test boolean not null default false
);

create index spec_satisfaction_ratings_project_idx
  on public.spec_satisfaction_ratings (spec_project_id, milestone);

-- ─── 11. spec_support_tickets ────────────────────────────────────────────
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

-- ─── 13. spec_communications ─────────────────────────────────────────────
create table public.spec_communications (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  direction text not null check (direction in ('outbound', 'inbound')),
  channel text not null check (channel in ('email', 'admin_note', 'call_log', 'video_message', 'system')),
  summary text not null,
  body text,
  occurred_at timestamptz default now(),
  logged_by_user_id uuid references public.users(id) on delete set null,
  is_test boolean not null default false
);

create index spec_communications_project_idx
  on public.spec_communications (spec_project_id, occurred_at desc);

-- ─── 16. spec_blocked_buyers ─────────────────────────────────────────────
-- citext extension installed by Migration 1.
create table public.spec_blocked_buyers (
  id uuid primary key default gen_random_uuid(),
  email citext not null,
  stripe_customer_id text,
  blocked_at timestamptz default now(),
  blocked_reason text not null,
  blocked_by_user_id uuid references public.users(id) on delete set null,
  unblocked_at timestamptz
);

create unique index spec_blocked_buyers_email_idx
  on public.spec_blocked_buyers (email) where unblocked_at is null;

create index spec_blocked_buyers_stripe_customer_idx
  on public.spec_blocked_buyers (stripe_customer_id) where unblocked_at is null and stripe_customer_id is not null;
