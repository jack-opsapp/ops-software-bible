-- Subscription-feed tokens for the read-only site-visit calendar.
--
-- A calendar client cannot send an auth header or run OAuth, so the secret has
-- to live in the URL. That makes three things mandatory:
--   1. the token is long and random (32 bytes, base64url)
--   2. only its SHA-256 is stored, so a database leak never yields live URLs
--   3. it is revocable, and regenerating instantly kills the previous URL
create table if not exists public.calendar_feed_tokens (
  id           uuid primary key default gen_random_uuid(),
  company_id   text not null,
  user_id      uuid not null references public.users(id) on delete cascade,
  -- SHA-256 hex of the token. The plaintext is shown once, at mint time, and
  -- never persisted.
  token_hash   text not null unique,
  label        text,
  created_at   timestamptz not null default now(),
  revoked_at   timestamptz,
  last_accessed_at timestamptz,
  access_count bigint not null default 0
);

-- One live feed per user. Minting again revokes the old URL rather than
-- accumulating forgotten, still-working links.
create unique index if not exists calendar_feed_tokens_one_active_per_user
  on public.calendar_feed_tokens (user_id)
  where revoked_at is null;

create index if not exists calendar_feed_tokens_company
  on public.calendar_feed_tokens (company_id);

alter table public.calendar_feed_tokens enable row level security;

-- Server-only. The feed route resolves the token with the service role; there
-- is no client-side read path, and no policy grants one.
create policy calendar_feed_tokens_service_all
  on public.calendar_feed_tokens
  for all
  to service_role
  using (true)
  with check (true);

comment on table public.calendar_feed_tokens is
  'Bearer tokens for the read-only site-visit iCalendar feed (Apple Calendar / Outlook). Only the SHA-256 is stored; one active token per user.';
