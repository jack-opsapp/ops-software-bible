-- Feed the calendar queue from the TABLE, not from each caller.
--
-- site_visits has several writers: the web "Create Site Visit" modal, the
-- confirmation-triggered booking RPC, and the iOS app's outbox. Wiring an
-- enqueue call into each one guarantees the next writer forgets. A trigger
-- covers every present and future writer exactly once.

create or replace function public.enqueue_google_calendar_sync()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_connection_id uuid;
  v_operation     text;
  v_company_uuid  uuid;
begin
  -- site_visits.company_id is legacy text; the queue is uuid.
  begin
    v_company_uuid := nullif(btrim(coalesce(new.company_id, old.company_id)), '')::uuid;
  exception when others then
    return coalesce(new, old);
  end;
  if v_company_uuid is null then
    return coalesce(new, old);
  end if;

  -- Decide the operation. A soft delete or a cancellation removes the event;
  -- everything else creates or updates it.
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

  -- Never queue work for a visit with no time, and never resurrect the past.
  if v_operation <> 'delete' and coalesce(new.scheduled_at, old.scheduled_at) is null then
    return coalesce(new, old);
  end if;

  -- The mailbox whose calendar this lands on. Only a connection that actually
  -- granted the calendar scope is eligible; without one there is nothing to
  -- push to and the row is simply not queued.
  select ec.id
    into v_connection_id
    from public.email_connections ec
   where ec.company_id = v_company_uuid
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
$$;

-- The worker writes google_calendar_event_id back onto the row; that write must
-- not re-enqueue itself. Listing the watched columns keeps it from looping.
drop trigger if exists trg_site_visits_google_calendar_sync on public.site_visits;
create trigger trg_site_visits_google_calendar_sync
  after insert or update of scheduled_at, duration_minutes, notes, status, deleted_at
  on public.site_visits
  for each row
  execute function public.enqueue_google_calendar_sync();

comment on function public.enqueue_google_calendar_sync() is
  'Queues a Google Calendar push whenever a site visit is created, rescheduled, cancelled, or deleted. Table-level so every writer (web modal, booking RPC, iOS outbox) is covered exactly once.';
