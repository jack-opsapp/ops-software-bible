create table if not exists calendar_user_events (
  id            uuid primary key default gen_random_uuid(),
  user_id       text not null,
  company_id    text not null,
  type          text not null check (type in ('personal', 'time_off')),
  title         text not null default '',
  start_date    timestamptz not null,
  end_date      timestamptz not null,
  all_day       boolean not null default true,
  notes         text,
  status        text not null default 'none' check (status in ('none', 'pending', 'approved', 'denied')),
  reviewed_by   text,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz,
  deleted_at    timestamptz
);

create index if not exists idx_calendar_user_events_user_id
  on calendar_user_events(user_id);

create index if not exists idx_calendar_user_events_company_id
  on calendar_user_events(company_id);

create index if not exists idx_calendar_user_events_date_range
  on calendar_user_events(start_date, end_date);

alter table calendar_user_events enable row level security;

create policy "Users manage own events"
  on calendar_user_events
  for all
  using (user_id = CAST(auth.uid() AS TEXT));

create policy "Company members read all events"
  on calendar_user_events
  for select
  using (
    company_id in (
      select CAST(company_id AS TEXT) from users where id = auth.uid()
    )
  );
