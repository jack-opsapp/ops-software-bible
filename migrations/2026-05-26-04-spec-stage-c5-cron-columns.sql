-- Stage C.5 (P1-2-12) — SPEC daily cron idempotency columns.
--
-- Source spec: ops-software-bible/SPEC/07_ROLLOUT.md § 12 (Cron jobs) +
-- ops-software-bible/SPEC/06_CONTRACT_AND_EMAIL.md § Cron jobs.
--
-- Adds the timestamp + counter columns the Vercel cron uses to guarantee
-- each scheduled nudge fires exactly once per project per stage:
--
--   spec_projects.last_intake_reminder_at
--   spec_projects.intake_reminder_count
--     → drives the D14 / D21 / D28 intake reminder sequence
--       (template_ids spec.intake_reminder_1/_2/_3). The brief in
--       07_ROLLOUT.md mentions D14 / D30 / D60 alternates in some
--       passages; the cron uses 14 / 21 / 28 days (consistent with the
--       resolved Stage H template registry and the locked
--       06_CONTRACT_AND_EMAIL.md trigger table; the D30/D60 wording in
--       a single sentence of 03_WORKFLOW.md is documentation drift and
--       will be reconciled in the bible companion update).
--
--   spec_projects.last_intake_no_discovery_reminder_at
--   spec_projects.intake_no_discovery_reminder_count
--     → drives the D7 / D14 / D21 no-discovery sequence
--       (template_ids spec.intake_completed_no_discovery_1/_2/_3).
--
--   spec_projects.ops_blocked_review_reminder_sent_at
--     → idempotency for the 14-day-old ops_blocked operator notification.
--
--   spec_owner_approval_requests.expires_at
--     → 7-day token expiry anchor. C.3's owner-approval route does not
--       set this column today; the default below ensures new rows are
--       always populated, and the backfill statement covers any
--       existing pending rows. The cron picks up `status='pending' AND
--       expires_at < now()` and flips to `'expired'`.
--
-- All ADDs are idempotent (`add column if not exists`) so this migration
-- can be re-applied without harm. Counts default to 0 so existing rows
-- need no backfill for those.
--
-- Applied to live Supabase project ijeekuhbatykdomumfjx via MCP on 2026-05-26.

alter table public.spec_projects
  add column if not exists last_intake_reminder_at timestamptz,
  add column if not exists intake_reminder_count int not null default 0,
  add column if not exists last_intake_no_discovery_reminder_at timestamptz,
  add column if not exists intake_no_discovery_reminder_count int not null default 0,
  add column if not exists ops_blocked_review_reminder_sent_at timestamptz;

-- Cron index: find candidates for intake reminders quickly.
create index if not exists spec_projects_intake_reminder_cron_idx
  on public.spec_projects (deposit_paid_at, intake_reminder_count)
  where status = 'deposit_paid'
    and intake_completed_at is null;

-- Cron index: find candidates for no-discovery reminders quickly.
create index if not exists spec_projects_no_discovery_reminder_cron_idx
  on public.spec_projects (intake_completed_at, intake_no_discovery_reminder_count)
  where intake_completed_at is not null
    and discovery_scheduled_at is null;

alter table public.spec_owner_approval_requests
  add column if not exists expires_at timestamptz;

-- Backfill any existing pending requests with the 7-day default anchor.
update public.spec_owner_approval_requests
  set expires_at = requested_at + interval '7 days'
  where expires_at is null;

-- Default for new rows. C.3's POST /api/spec/owner-approval/[token] route
-- can also set this explicitly when issuing a request, but the default
-- guarantees the cron has something to anchor on even if a sibling chip
-- ships before its route is updated.
alter table public.spec_owner_approval_requests
  alter column expires_at set default (now() + interval '7 days');

-- Cron index: find expired pending approvals quickly.
create index if not exists spec_owner_approval_requests_expiry_cron_idx
  on public.spec_owner_approval_requests (expires_at)
  where status = 'pending';
