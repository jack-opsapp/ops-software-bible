-- SPEC Phase 1 — Migration 1/8: Enums + spec_capacity seed + citext extension
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md
-- Applied: 2026-05-25 via Supabase MCP apply_migration as `spec_phase1_enums_and_capacity`.
-- Verified live schema 2026-05-25: citext not yet installed (idempotent create handles it).

create extension if not exists citext;

create type spec_project_status as enum (
  'awaiting_owner_approval',
  'awaiting_deposit',
  'deposit_paid',
  'discovery',
  'building',
  'on_hold',
  'stalled_on_hold',
  'support',
  'on_retainer',
  'completed',
  'stalled',
  'cancelled',
  'refunded'
);

create type spec_hold_type as enum (
  'customer_requested',
  'ops_blocked'
);

create type spec_owner_approval_status as enum (
  'pending',
  'approved',
  'declined',
  'expired'
);

create type spec_payment_milestone as enum (
  'deposit',
  'scope_signoff',
  'midpoint',
  'delivery'
);

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

create type spec_change_order_type as enum (
  'minor_hourly',
  'major_fixed',
  'polish_budget',
  'platform_compat_rebuild',
  'tier_upgrade'
);

create type spec_change_order_status as enum (
  'proposed',
  'customer_approved',
  'customer_declined',
  'in_progress',
  'completed',
  'paid'
);

create type spec_feature_status as enum ('pending', 'passing', 'failing');

create type spec_ticket_severity as enum ('critical', 'high', 'cosmetic_enhancement');
create type spec_ticket_status as enum ('open', 'in_progress', 'resolved', 'escalated_to_change_order');
create type spec_ticket_phase as enum ('support', 'retainer', 'ad_hoc');

create type spec_retainer_status as enum ('active', 'paused', 'cancelled');

create type spec_refund_status as enum ('pending', 'processed', 'partial', 'failed', 'denied');
create type spec_refund_source as enum ('customer_initiated', 'stripe_dispute');

create type spec_referral_status as enum (
  'pending',
  'eligible',
  'kyc_required',
  'review',
  'paid',
  'forfeited',
  'held'
);

create table public.spec_capacity (
  tier text primary key check (tier in ('setup', 'build', 'enterprise')),
  slot_ceiling int not null,
  manual_next_start_override date,
  is_accepting_bookings boolean not null default true,
  public_note text,
  discovery_days_min int not null,
  discovery_days_max int not null,
  build_days_min int not null,
  build_days_max int not null,
  support_window_days int not null,
  total_price_cents int not null,
  subscription_multiplier_estimate numeric(4,2) not null,
  retainer_monthly_cents int not null,
  polish_hours_budget numeric(4,2) not null,
  admin_notes text,
  updated_at timestamptz default now()
);

insert into public.spec_capacity (
  tier, slot_ceiling, manual_next_start_override, is_accepting_bookings, public_note,
  discovery_days_min, discovery_days_max, build_days_min, build_days_max, support_window_days,
  total_price_cents, subscription_multiplier_estimate, retainer_monthly_cents, polish_hours_budget,
  admin_notes, updated_at
) values
  ('setup',      4, null, true, null, 3,  5,  7,  14, 30,   300000, 0.15, 25000, 2, null, now()),
  ('build',      3, null, true, null, 5,  7, 14,  21, 60,   850000, 0.30, 45000, 4, null, now()),
  ('enterprise', 1, null, true, null, 7, 14, 28,  42, 90,  1800000, 0.50, 75000, 8, null, now());
