-- SITE VISIT BOOKING — booking discriminator, reminder plumbing, prompt dedupe backbone.
-- Design: ops-software-bible/specs/2026-08-10-site-visit-booking-calendar-design.md
-- All changes additive (iOS shipping-app constraint).

-- 1) Booking discriminator + per-booking reminder override
alter table public.site_visits
  add column if not exists booked_at timestamptz,
  add column if not exists reminder_lead_minutes int
    check (reminder_lead_minutes is null or reminder_lead_minutes between 0 and 1440);

comment on column public.site_visits.booked_at is
  'Non-null = this visit is a real appointment; scheduled_at is then meaningful. NULL = walk-up/legacy (scheduled_at is junk, defaulted to created_at).';
comment on column public.site_visits.reminder_lead_minutes is
  'Per-booking heads-up override in minutes. NULL = use the assignee''s notification_preferences.site_visit_reminder_lead_minutes, else product default 30.';

-- 2) Booked-visit scheduling queries (calendars, prompt cron, MCP reads)
create index if not exists site_visits_booked_window_idx
  on public.site_visits (company_id, scheduled_at)
  where booked_at is not null and deleted_at is null;

-- 3) Per-user default heads-up lead (NULL = product default 30)
alter table public.notification_preferences
  add column if not exists site_visit_reminder_lead_minutes int
    check (site_visit_reminder_lead_minutes is null or site_visit_reminder_lead_minutes between 0 and 1440);

comment on column public.notification_preferences.site_visit_reminder_lead_minutes is
  'Default heads-up lead time for booked site visits, minutes before scheduled_at. NULL = product default 30.';

-- 4) Prompt idempotency backbone.
-- Deliberately scoped to site-visit prompt keys, NOT a global unique index:
-- other producers (lead_lifecycle:*, task-mutation:*, project-status-lifecycle:*)
-- legitimately re-fire the same dedupe_key after a notification is read/resolved,
-- and every existing unique index on this table is scoped for exactly that reason.
-- Site-visit prompt keys are site_visit:<visit_id>:<kind>:<user_id>:<epoch(scheduled_at)>
-- (unique per prompt forever; a reschedule changes the epoch and re-arms by construction).
-- Writers must insert with: on conflict (dedupe_key) where dedupe_key like 'site_visit:%' do nothing
create unique index if not exists notifications_site_visit_prompt_dedupe_uidx
  on public.notifications (dedupe_key)
  where dedupe_key like 'site_visit:%';

-- 5) Google sync queue: bookings only.
-- The deployed trigger enqueues on EVERY site_visits insert/update once a
-- calendar-scoped connection exists. Booking semantics make walk-up/legacy rows
-- (booked_at IS NULL) carry junk scheduled_at — they must never reach any
-- calendar surface. Gate the enqueue on the booking discriminator.
create or replace function public.enqueue_google_calendar_sync()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_connection_id uuid;
  v_operation     text;
  v_company_text  text;
  v_company_uuid  uuid;
begin
  -- Only booked appointments sync to Google. Walk-up captures and legacy rows
  -- (booked_at IS NULL) have meaningless scheduled_at values and must stay off
  -- every calendar surface.
  if coalesce(new.booked_at, old.booked_at) is null then
    return coalesce(new, old);
  end if;

  v_company_text := btrim(coalesce(new.company_id, old.company_id));
  if v_company_text is null or v_company_text = '' then
    return coalesce(new, old);
  end if;

  -- The queue is uuid-keyed; a malformed legacy tenant id must never abort the
  -- caller's write, so the cast failing is a no-op, not an error.
  begin
    v_company_uuid := v_company_text::uuid;
  exception when others then
    return coalesce(new, old);
  end;

  if tg_op = 'INSERT' then
    v_operation := 'create';
  elsif new.deleted_at is not null and old.deleted_at is null then
    v_operation := 'delete';
  elsif new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    v_operation := 'delete';
  elsif new.scheduled_at is distinct from old.scheduled_at
     or new.duration_minutes is distinct from old.duration_minutes
     or new.notes is distinct from old.notes then
    -- Only schedule-visible changes are worth a Google write. Photos,
    -- measurements and internal notes never reach the calendar.
    v_operation := 'update';
  else
    return new;
  end if;

  if v_operation <> 'delete' and coalesce(new.scheduled_at, old.scheduled_at) is null then
    return coalesce(new, old);
  end if;

  -- A newly created visit is never queued as already-cancelled or deleted.
  if tg_op = 'INSERT' and (new.status = 'cancelled' or new.deleted_at is not null) then
    return new;
  end if;

  -- The mailbox whose calendar this lands on. Only a connection that actually
  -- granted the calendar scope is eligible; with none, nothing is queued and
  -- the feature is simply inert for that company.
  select ec.id
    into v_connection_id
    from public.email_connections ec
   where ec.company_id = v_company_text
     and ec.status = 'active'
     and ec.granted_scopes && array[
           'https://www.googleapis.com/auth/calendar.events',
           'https://www.googleapis.com/auth/calendar'
         ]
   order by ec.created_at
   limit 1;

  if v_connection_id is null then
    return coalesce(new, old);
  end if;

  insert into public.google_calendar_sync_queue (
    company_id, connection_id, site_visit_id, operation,
    google_calendar_id, google_calendar_event_id, status
  )
  values (
    v_company_uuid,
    v_connection_id,
    coalesce(new.id, old.id),
    v_operation,
    coalesce(new.google_calendar_id, old.google_calendar_id),
    coalesce(new.google_calendar_event_id, old.google_calendar_event_id),
    'pending'
  )
  on conflict (site_visit_id, operation) where status = 'pending'
  do update set
    google_calendar_event_id = excluded.google_calendar_event_id,
    google_calendar_id       = excluded.google_calendar_id,
    next_attempt_at          = now(),
    updated_at               = now();

  return coalesce(new, old);
end;
$function$;
