-- Stage C.1 (P1-2-6) — SPEC checkout-flow outboxes.
--
-- Applied to live Supabase project ijeekuhbatykdomumfjx via MCP on 2026-05-26.
-- Mirrored here for tree-of-truth + future replay against fresh environments.
--
-- conversion_event_outbox  → Meta CAPI + Google Enhanced server-side sends.
--                             The Stage C.5 cron (deferred) picks up status='pending'
--                             rows hourly and posts to the ad-platform APIs once
--                             Meta CAPI + Google Enhanced credentials are
--                             provisioned (see SPEC/07_ROLLOUT.md open item #8).
-- spec_email_outbox        → SPEC transactional emails. ops-site writes from
--                             /api/spec/create-checkout-session (Stage C.1) and
--                             future webhook + owner-approval routes; OPS-Web
--                             dispatches via the Stage H React Email templates
--                             registered against `template_id`.
--
-- Both tables are operator/service-role owned: customer clients never read or
-- write them. RLS posture matches the SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION
-- lock (see SPEC/07_ROLLOUT.md § Gate resolutions).

create extension if not exists pgcrypto;

create table if not exists public.conversion_event_outbox (
  id uuid primary key default gen_random_uuid(),
  event_name text not null,
  payload jsonb not null,
  attempts int not null default 0,
  last_attempt_at timestamptz,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed', 'permanent_failure')),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists conversion_event_outbox_status_idx
  on public.conversion_event_outbox (status, created_at)
  where status = 'pending';

alter table public.conversion_event_outbox enable row level security;

drop policy if exists "conversion_event_outbox no public access" on public.conversion_event_outbox;
create policy "conversion_event_outbox no public access"
  on public.conversion_event_outbox
  for all using (false) with check (false);

create table if not exists public.spec_email_outbox (
  id uuid primary key default gen_random_uuid(),
  template_id text not null,
  recipient_email text not null,
  recipient_user_id uuid references public.users(id) on delete set null,
  spec_project_id uuid references public.spec_projects(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  attempts int not null default 0,
  last_attempt_at timestamptz,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed', 'permanent_failure')),
  last_error text,
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists spec_email_outbox_status_idx
  on public.spec_email_outbox (status, created_at)
  where status = 'pending';
create index if not exists spec_email_outbox_project_idx
  on public.spec_email_outbox (spec_project_id);

alter table public.spec_email_outbox enable row level security;

drop policy if exists "spec_email_outbox no public access" on public.spec_email_outbox;
create policy "spec_email_outbox no public access"
  on public.spec_email_outbox
  for all using (false) with check (false);
