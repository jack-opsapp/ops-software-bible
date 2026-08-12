-- Phase 2 (Inbox Clean-State Layer): per-attachment metadata + vision inspection cache.
-- ADDITIVE / iOS-SAFE: two brand-new tables, no changes to existing objects.
-- Rollback (sentinel):
--   drop table if exists public.attachment_inspections;
--   drop table if exists public.email_attachments;

create table if not exists public.email_attachments (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  connection_id      uuid,
  provider_thread_id text not null,
  message_id         text not null,
  attachment_id      text not null,
  filename           text,
  mime_type          text,
  size_bytes         bigint,
  from_email         text,
  created_at         timestamptz not null default now(),
  unique (company_id, message_id, attachment_id)
);

create index if not exists email_attachments_company_thread_idx
  on public.email_attachments (company_id, provider_thread_id);

create table if not exists public.attachment_inspections (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  provider_thread_id text,
  message_id         text not null,
  attachment_id      text not null,
  summary            text,
  is_signed_estimate boolean not null default false,
  facts              jsonb not null default '{}'::jsonb,
  model              text,
  inspected_at       timestamptz not null default now(),
  unique (company_id, message_id, attachment_id)
);

create index if not exists attachment_inspections_company_thread_idx
  on public.attachment_inspections (company_id, provider_thread_id);

alter table public.email_attachments       enable row level security;
alter table public.attachment_inspections  enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'email_attachments'
      and policyname = 'email_attachments_company_scope'
  ) then
    create policy email_attachments_company_scope on public.email_attachments
      for all
      using (company_id = ((auth.jwt() ->> 'company_id'::text))::uuid);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'attachment_inspections'
      and policyname = 'attachment_inspections_company_scope'
  ) then
    create policy attachment_inspections_company_scope on public.attachment_inspections
      for all
      using (company_id = ((auth.jwt() ->> 'company_id'::text))::uuid);
  end if;
end$$;

grant select, insert, update, delete on public.email_attachments      to anon, authenticated, service_role;
grant select, insert, update, delete on public.attachment_inspections to anon, authenticated, service_role;

comment on table public.email_attachments is
  'Per-attachment provider identity (message_id + attachment_id + filename/mime/size + sender) captured at ingestion so the inbox vision inspector can fetch a specific attachment''s bytes. Phase 2, Inbox Clean-State Layer.';
comment on table public.attachment_inspections is
  'OpenAI vision verdict cache, keyed UNIQUE (company_id, message_id, attachment_id) for cost-once inspection. Read by the deterministic conversation-state layer (which never calls vision). Phase 2, Inbox Clean-State Layer.';
