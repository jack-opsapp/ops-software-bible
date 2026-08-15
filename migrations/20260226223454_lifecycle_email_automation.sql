
-- Enable pg_cron and pg_net if not already enabled
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ── WEBHOOK 1: users UPDATE → onboarding complete ──────────────────────────
-- Fires when has_completed_onboarding flips to true on a Company user
create or replace function trigger_lifecycle_onboarding_complete()
returns trigger language plpgsql as $$
begin
  -- Only fire if onboarding just became true
  if (new.has_completed_onboarding = true and
      (old.has_completed_onboarding is distinct from true)) then
    perform net.http_post(
      url     := current_setting('app.supabase_url') || '/functions/v1/lifecycle-onboarding-complete',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
      ),
      body    := jsonb_build_object(
        'record',     to_jsonb(new),
        'old_record', to_jsonb(old)
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_onboarding_complete on public.users;
create trigger on_onboarding_complete
  after update on public.users
  for each row execute function trigger_lifecycle_onboarding_complete();

-- ── WEBHOOK 2: projects INSERT → first action ───────────────────────────────
create or replace function trigger_lifecycle_first_project()
returns trigger language plpgsql as $$
begin
  perform net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/lifecycle-first-action',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key')
    ),
    body    := jsonb_build_object(
      'record', to_jsonb(new),
      'table',  'projects'
    )
  );
  return new;
end;
$$;

drop trigger if exists on_first_project on public.projects;
create trigger on_first_project
  after insert on public.projects
  for each row execute function trigger_lifecycle_first_project();

-- ── WEBHOOK 3: clients INSERT → first action ────────────────────────────────
create or replace function trigger_lifecycle_first_client()
returns trigger language plpgsql as $$
begin
  perform net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/lifecycle-first-action',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key')
    ),
    body    := jsonb_build_object(
      'record', to_jsonb(new),
      'table',  'clients'
    )
  );
  return new;
end;
$$;

drop trigger if exists on_first_client on public.clients;
create trigger on_first_client
  after insert on public.clients
  for each row execute function trigger_lifecycle_first_client();

-- ── pg_cron: daily lifecycle job at 9am UTC ─────────────────────────────────
select cron.unschedule('lifecycle-daily-cron')
  where exists (
    select 1 from cron.job where jobname = 'lifecycle-daily-cron'
  );

select cron.schedule(
  'lifecycle-daily-cron',
  '0 9 * * *',  -- 9am UTC daily (2am PST / 5am EST)
  $$
  select net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/lifecycle-cron',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-cron-secret',  current_setting('app.cron_secret')
    ),
    body    := '{}'::jsonb
  )
  $$
);

