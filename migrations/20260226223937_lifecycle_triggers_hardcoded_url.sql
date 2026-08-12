
-- Recreate triggers with hardcoded project URL and webhook secret header
-- CRON_SECRET is shared between pg_cron → lifecycle-cron and these DB triggers

create or replace function trigger_lifecycle_onboarding_complete()
returns trigger language plpgsql as $$
begin
  if (new.has_completed_onboarding = true and
      (old.has_completed_onboarding is distinct from true)) then
    perform net.http_post(
      url     := 'https://ijeekuhbatykdomumfjx.supabase.co/functions/v1/lifecycle-onboarding-complete',
      headers := jsonb_build_object(
        'Content-Type',    'application/json',
        'x-webhook-secret', current_setting('app.webhook_secret', true)
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

create or replace function trigger_lifecycle_first_project()
returns trigger language plpgsql as $$
begin
  perform net.http_post(
    url     := 'https://ijeekuhbatykdomumfjx.supabase.co/functions/v1/lifecycle-first-action',
    headers := jsonb_build_object(
      'Content-Type',    'application/json',
      'x-webhook-secret', current_setting('app.webhook_secret', true)
    ),
    body    := jsonb_build_object(
      'record', to_jsonb(new),
      'table',  'projects'
    )
  );
  return new;
end;
$$;

create or replace function trigger_lifecycle_first_client()
returns trigger language plpgsql as $$
begin
  perform net.http_post(
    url     := 'https://ijeekuhbatykdomumfjx.supabase.co/functions/v1/lifecycle-first-action',
    headers := jsonb_build_object(
      'Content-Type',    'application/json',
      'x-webhook-secret', current_setting('app.webhook_secret', true)
    ),
    body    := jsonb_build_object(
      'record', to_jsonb(new),
      'table',  'clients'
    )
  );
  return new;
end;
$$;

-- Update pg_cron job to also use webhook secret
select cron.unschedule('lifecycle-daily-cron')
  where exists (
    select 1 from cron.job where jobname = 'lifecycle-daily-cron'
  );

select cron.schedule(
  'lifecycle-daily-cron',
  '0 9 * * *',
  $$
  select net.http_post(
    url     := 'https://ijeekuhbatykdomumfjx.supabase.co/functions/v1/lifecycle-cron',
    headers := jsonb_build_object(
      'Content-Type',    'application/json',
      'x-cron-secret',   current_setting('app.webhook_secret', true)
    ),
    body    := '{}'::jsonb
  )
  $$
);

