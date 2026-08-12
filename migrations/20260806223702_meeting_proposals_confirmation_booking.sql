-- Confirmation-triggered site-visit booking.
-- docs/inbox/confirmation-triggered-booking-spec.md
--
-- A `meeting_proposal` is written at SEND time, when OPS itself names a
-- specific datetime in an outbound email. It is the source of truth for that
-- instant, so a later customer acceptance only has to point at it — the system
-- never has to read a datetime out of arbitrary inbound mail.

begin;

create table if not exists public.meeting_proposals (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references public.companies (id) on delete cascade,
  opportunity_id      uuid not null references public.opportunities (id) on delete cascade,
  connection_id       uuid not null references public.email_connections (id) on delete cascade,
  provider_thread_id  text not null,
  source_activity_id  uuid not null references public.activities (id) on delete cascade,
  proposed_start_at   timestamptz not null,
  duration_minutes    integer not null default 60,
  time_zone           text not null,
  proposal_text       text not null,
  proposed_by_user_id uuid not null references public.users (id),
  status              text not null default 'pending',
  accepted_message_id text,
  accepted_at         timestamptz,
  site_visit_id       uuid references public.site_visits (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint meeting_proposals_status_valid
    check (status in ('pending', 'accepted', 'superseded', 'expired', 'declined')),
  constraint meeting_proposals_duration_sane
    check (duration_minutes > 0 and duration_minutes <= 480)
);

-- Capture is idempotent under send retry: one proposal per outbound message.
create unique index if not exists meeting_proposals_source_activity_key
  on public.meeting_proposals (connection_id, source_activity_id);

-- At most one live proposal per thread. A newer proposal supersedes the older.
create unique index if not exists meeting_proposals_one_pending_per_thread
  on public.meeting_proposals (connection_id, provider_thread_id)
  where status = 'pending';

create index if not exists meeting_proposals_opportunity_idx
  on public.meeting_proposals (opportunity_id, status);

create index if not exists meeting_proposals_site_visit_idx
  on public.meeting_proposals (site_visit_id);

alter table public.meeting_proposals enable row level security;

-- Read-only to the owning company; every write goes through the service role
-- or the guarded RPC below.
drop policy if exists meeting_proposals_company_read on public.meeting_proposals;
create policy meeting_proposals_company_read
  on public.meeting_proposals
  for select
  using (company_id = (select private.get_user_company_id()));

grant select on public.meeting_proposals to authenticated;

commit;
