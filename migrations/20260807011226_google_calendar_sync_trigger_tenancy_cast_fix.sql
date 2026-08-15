-- Fix: email_connections.company_id is legacy TEXT, not uuid, so comparing it
-- to a uuid threw 42883 and every site-visit insert failed. Same text/uuid
-- tenancy split that site_visits carries; compare on text.

create or replace function public.enqueue_google_calendar_sync()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_connection_id uuid;
  v_operation     text;
  v_company_text  text;
  v_company_uuid  uuid;
begin
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
$$;
