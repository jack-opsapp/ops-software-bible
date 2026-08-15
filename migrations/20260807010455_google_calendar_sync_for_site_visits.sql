-- Google Calendar push for site visits.
-- docs/plans/2026-08-06-site-visits-on-schedule-and-google-calendar.md, Workstream B.

-- 1) Which scopes a mailbox connection actually granted.
--
-- A connection authorised before the calendar scope was requested holds a
-- refresh token that can only touch mail. Without this column every calendar
-- push on an old connection would 403 forever. Recording the grant lets the
-- queue stay INERT on those connections instead of failing loudly.
alter table public.email_connections
  add column if not exists granted_scopes text[];

comment on column public.email_connections.granted_scopes is
  'OAuth scopes the provider actually granted, from the token response. Null = pre-dates scope recording; treat as mail-only.';

-- Backfill: every existing connection was authorised with mail-only scope.
update public.email_connections
   set granted_scopes = array['https://mail.google.com/']
 where granted_scopes is null
   and provider = 'gmail';

-- 2) Where a site visit landed on Google Calendar.
--
-- Deliberately NOT reusing the legacy `calendar_event_id`: that belongs to the
-- dead `calendar_events` table (0 rows) and overloading it would make a
-- long-obsolete column ambiguous forever.
alter table public.site_visits
  add column if not exists google_calendar_event_id text,
  add column if not exists google_calendar_id text,
  add column if not exists google_calendar_synced_at timestamptz;

comment on column public.site_visits.google_calendar_event_id is
  'Google Calendar event id for this visit. Null = never pushed.';
comment on column public.site_visits.google_calendar_id is
  'Google calendar the event lives on (normally the mailbox primary).';

-- One OPS visit maps to at most one Google event per calendar.
create unique index if not exists site_visits_google_event_unique
  on public.site_visits (google_calendar_id, google_calendar_event_id)
  where google_calendar_event_id is not null;
