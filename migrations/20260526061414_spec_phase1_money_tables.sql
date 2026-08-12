-- SPEC Phase 1 — Migration 5/8: Money tables (payments, change orders, refunds, referrals, retainers)
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md
-- CR-4: spec_payments status enum extended (voided, partially_refunded, uncollectible).
-- CR-4: spec_refund_requests.refund_breakdown jsonb stores per-milestone action.
-- MN-6: spec_referrals.ytd_referrer_payout_cents removed (derived at query time).
-- Spec_referrals has bounty default $500 CAD = 50000 cents.

-- ─── 7. spec_payments ────────────────────────────────────────────────────
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
  credit_note_stripe_id text,
  created_at timestamptz default now(),
  is_test boolean not null default false
);

create unique index spec_payments_project_milestone_idx
  on public.spec_payments (spec_project_id, milestone);

-- ─── 8. spec_change_orders ───────────────────────────────────────────────
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
  acceptance_event_id uuid references public.spec_acceptance_events(id),
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

create index spec_change_orders_project_idx
  on public.spec_change_orders (spec_project_id, status);

-- ─── 14. spec_refund_requests ────────────────────────────────────────────
create table public.spec_refund_requests (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null references public.spec_projects(id) on delete cascade,
  request_source spec_refund_source not null,
  customer_reason_text text,
  requested_at timestamptz default now(),
  processed_at timestamptz,
  processed_by_user_id uuid references public.users(id) on delete set null,
  refund_breakdown jsonb,
  total_refund_cents int,
  stripe_refund_ids jsonb,
  is_goodwill boolean default false,
  is_guarantee_invocation boolean default false,
  status spec_refund_status not null default 'pending',
  is_test boolean not null default false
);

-- One soft-guarantee invocation per engagement (enforced).
create unique index spec_refund_one_guarantee_per_project_idx
  on public.spec_refund_requests (spec_project_id)
  where is_guarantee_invocation = true and status in ('pending', 'processed', 'partial');

create index spec_refund_requests_project_idx
  on public.spec_refund_requests (spec_project_id, requested_at desc);

-- ─── 15. spec_referrals ──────────────────────────────────────────────────
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

-- ─── 12. spec_retainers ──────────────────────────────────────────────────
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

create index spec_retainers_project_idx on public.spec_retainers (spec_project_id, status);
