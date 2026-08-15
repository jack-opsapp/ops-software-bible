alter table public.opportunities
  add column if not exists source_thread_key text;

alter table public.email_connections
  add column if not exists sync_in_progress_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'opportunities_company_source_thread_key_key'
  ) then
    alter table public.opportunities
      add constraint opportunities_company_source_thread_key_key
      unique (company_id, source_thread_key);
  end if;
end$$;

comment on column public.opportunities.source_thread_key is
  'Provider email thread id for email-sourced leads, set at creation. UNIQUE (company_id, source_thread_key) dedupes opportunities per email thread (P0-A). NULL for non-email or pre-existing leads (NULLs are distinct).';
comment on column public.email_connections.sync_in_progress_at is
  'Per-connection sync lock timestamp. Claimed at the top of runSync, released in finally; stale locks expire after the app TTL. Serializes webhook + cron syncs (P0-A).';
