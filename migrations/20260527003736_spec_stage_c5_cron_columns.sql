-- Stage C.5 (P1-2-12) — SPEC daily cron idempotency columns.
-- Mirrors ops-software-bible/migrations/2026-05-26-04-spec-stage-c5-cron-columns.sql

alter table public.spec_projects
  add column if not exists last_intake_reminder_at timestamptz,
  add column if not exists intake_reminder_count int not null default 0,
  add column if not exists last_intake_no_discovery_reminder_at timestamptz,
  add column if not exists intake_no_discovery_reminder_count int not null default 0,
  add column if not exists ops_blocked_review_reminder_sent_at timestamptz;

create index if not exists spec_projects_intake_reminder_cron_idx
  on public.spec_projects (deposit_paid_at, intake_reminder_count)
  where status = 'deposit_paid'
    and intake_completed_at is null;

create index if not exists spec_projects_no_discovery_reminder_cron_idx
  on public.spec_projects (intake_completed_at, intake_no_discovery_reminder_count)
  where intake_completed_at is not null
    and discovery_scheduled_at is null;

alter table public.spec_owner_approval_requests
  add column if not exists expires_at timestamptz;

update public.spec_owner_approval_requests
  set expires_at = requested_at + interval '7 days'
  where expires_at is null;

alter table public.spec_owner_approval_requests
  alter column expires_at set default (now() + interval '7 days');

create index if not exists spec_owner_approval_requests_expiry_cron_idx
  on public.spec_owner_approval_requests (expires_at)
  where status = 'pending';

