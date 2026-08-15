-- ============================================================================
-- email_templates — create table with Firebase-bridged RLS (drift remediation)
--
-- BACKGROUND: legacy migration 039_email_templates.sql was committed (Feb/Mar
-- 2026) but NEVER applied to prod. public.email_templates did not exist, yet
-- live code reads it:
--   • src/lib/api/services/email-template-service.ts  (.from("email_templates"))
--   • Settings → Email Templates tab, pipeline-list widget, compose-email form
-- Every call has been failing with PostgREST PGRST205 ("table not found").
-- This is the same class of bug as 20260519000000_dimensioned_photo_*.
--
-- This recreates the table with 039's exact column contract (verified against
-- email-template-service.ts rowToTemplate / createTemplate / updateTemplate),
-- with two corrections required by THIS app's runtime:
--
--  1. RLS identity. OPS-Web reads as the Firebase-bridged anon role
--     (supabase/client.ts: persistSession:false → auth.uid() is NULL). 039's
--     auth.uid()-based RLS would leave the table returning ZERO rows even once
--     created (cf. accounting_connections bug eb70d803). We scope by
--     private.get_user_company_id() (uuid) and grant anon/authenticated,
--     mirroring public.clients.company_isolation.
--  2. created_by is a plain uuid (no FK): the UI passes currentUser.id
--     (public.users id, NOT auth.users id), so 039's FK to auth.users(id)
--     would have rejected every insert.
--
-- Purely additive + idempotent (IF NOT EXISTS / DROP-IF-EXISTS). iOS-sync-safe.
-- ============================================================================

begin;

create table if not exists public.email_templates (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  name        text not null,
  subject     text not null default '',
  body        text not null default '',
  category    text not null default 'general'
    check (category in ('follow_up', 'scheduling', 'estimate', 'invoice', 'introduction', 'general')),
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_email_templates_company
  on public.email_templates (company_id, category, sort_order)
  where is_active = true;

-- updated_at maintenance
create or replace function public.update_email_templates_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
begin
  new.updated_at = now();
  return new;
end;
$fn$;

drop trigger if exists trg_email_templates_updated_at on public.email_templates;
create trigger trg_email_templates_updated_at
  before update on public.email_templates
  for each row execute function public.update_email_templates_updated_at();

-- RLS: company isolation via the Firebase-bridge identity (anon-role safe)
alter table public.email_templates enable row level security;

drop policy if exists "email_templates_company_isolation" on public.email_templates;
create policy "email_templates_company_isolation"
  on public.email_templates
  for all
  using (company_id = (select private.get_user_company_id()))
  with check (company_id = (select private.get_user_company_id()));

grant select, insert, update, delete on public.email_templates to authenticated, anon;

-- PostgREST: pick up the new table immediately (avoid lingering PGRST205)
notify pgrst, 'reload schema';

-- ── sentinel guard: do not let a half-applied state commit ───────────────────
do $$
begin
  if to_regclass('public.email_templates') is null then
    raise exception 'email_templates_sentinel: table public.email_templates missing';
  end if;
  if not exists (
    select 1 from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relname = 'email_templates' and p.polname = 'email_templates_company_isolation'
  ) then
    raise exception 'email_templates_sentinel: company_isolation policy missing';
  end if;
end$$;

commit;
