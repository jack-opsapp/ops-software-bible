-- Durable retry queue for Google Calendar pushes.
--
-- Best-effort would be wrong here: a dropped push is INVISIBLE to the operator,
-- which is precisely the failure this whole feature exists to prevent. Modelled
-- on the existing sync-queue pattern.

create table if not exists public.google_calendar_sync_queue (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  connection_id     uuid not null references public.email_connections(id) on delete cascade,
  site_visit_id     uuid not null references public.site_visits(id) on delete cascade,
  operation         text not null check (operation in ('create', 'update', 'delete')),
  -- Captured at enqueue: a delete still needs the event id after the visit row
  -- has already been soft-deleted.
  google_calendar_id       text,
  google_calendar_event_id text,
  status            text not null default 'pending'
                    check (status in ('pending', 'succeeded', 'failed', 'skipped')),
  attempts          integer not null default 0,
  next_attempt_at   timestamptz not null default now(),
  last_error        text,
  -- Why a row was skipped rather than retried: 'scope_missing' means the
  -- connection pre-dates the calendar scope and must reconnect. Retrying that
  -- forever would burn quota and hide the real fix from the operator.
  skip_reason       text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- The worker's claim query: oldest due pending row first.
create index if not exists google_calendar_sync_queue_due
  on public.google_calendar_sync_queue (next_attempt_at)
  where status = 'pending';

create index if not exists google_calendar_sync_queue_visit
  on public.google_calendar_sync_queue (site_visit_id);

-- Collapse duplicate pending work for the same visit+operation. Re-saving a
-- visit five times must not produce five Google writes.
create unique index if not exists google_calendar_sync_queue_pending_unique
  on public.google_calendar_sync_queue (site_visit_id, operation)
  where status = 'pending';

alter table public.google_calendar_sync_queue enable row level security;

-- Server-only: the worker runs as service_role. No client reads or writes.
create policy google_calendar_sync_queue_service_all
  on public.google_calendar_sync_queue
  for all
  to service_role
  using (true)
  with check (true);

comment on table public.google_calendar_sync_queue is
  'Durable retry queue pushing site visits to the connected mailbox owner''s Google Calendar. Service-role only.';
