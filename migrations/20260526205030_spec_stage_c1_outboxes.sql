
-- Stage C.1 (P1-2-6) — SPEC checkout-flow outboxes.
--
-- conversion_event_outbox  → Meta CAPI + Google Enhanced server-side sends.
-- spec_email_outbox        → SPEC transactional emails (cross-system: ops-site
--                            writes; OPS-Web (via Stage H templates + Stage C.5
--                            cron) reads and dispatches).
--
-- Both tables are operator/service-role owned: customer clients never read or
-- write them. RLS is enabled with a single "no anon/auth access" posture.

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

-- Service-role only — no anon/authenticated policy.
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

