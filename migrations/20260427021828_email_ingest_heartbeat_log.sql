create table if not exists public.email_ingest_heartbeat_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  triggered_at timestamptz not null default now(),
  reason text not null
);

create index if not exists email_ingest_heartbeat_log_company_recent_idx
  on public.email_ingest_heartbeat_log (company_id, triggered_at desc);

alter table public.email_ingest_heartbeat_log enable row level security;
