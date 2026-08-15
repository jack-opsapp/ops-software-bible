-- Catalog Setup Wizard — single-session-per-company lock (plan Task 6.3 / spec
-- §16 "only one setup session at a time per company"). One mutable row per
-- company (company_id PK → mutual exclusion via upsert); session_id + heartbeat_at
-- are the columns the pure predicate needs. Net-new + additive → iOS-safe.

create table if not exists public.catalog_setup_session_locks (
  company_id   uuid primary key references public.companies(id) on delete cascade,
  session_id   text        not null,
  user_id      text,
  heartbeat_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.catalog_setup_session_locks is
  'Advisory single-session lock for the Catalog Setup Wizard — one row per company; '
  'heartbeat_at older than ~120s is treated as stale/released by the client predicate.';

alter table public.catalog_setup_session_locks enable row level security;

-- App-layer auth runs as the anon role bridged from Firebase; mirror the policy
-- pair that catalog_setup_save_requests already proves works for both roles. The
-- bridge-safe resolver private.get_user_company_id() scopes by JWT email, so it
-- never trips the auth.uid()::uuid cast that breaks under the Firebase bridge.
drop policy if exists "company_isolation" on public.catalog_setup_session_locks;
create policy "company_isolation"
  on public.catalog_setup_session_locks
  for all
  to authenticated
  using (company_id = (select private.get_user_company_id()))
  with check (company_id = (select private.get_user_company_id()));

drop policy if exists "firebase bridge catalog setup session locks company isolation"
  on public.catalog_setup_session_locks;
create policy "firebase bridge catalog setup session locks company isolation"
  on public.catalog_setup_session_locks
  for all
  to anon
  using (company_id = private.get_user_company_id())
  with check (company_id = private.get_user_company_id());

grant select, insert, update, delete
  on public.catalog_setup_session_locks
  to anon, authenticated;
