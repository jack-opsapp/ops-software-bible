-- Allow schedulers with time_off.approve to book or update time-off rows for
-- active members of their own company. Existing self-owned event policy remains
-- the path for normal self requests and personal events.

drop policy if exists "Time off approvers insert company events" on public.calendar_user_events;

create policy "Time off approvers insert company events"
on public.calendar_user_events
for insert
to public
with check (
  type = 'time_off'
  and status in ('pending', 'approved')
  and private.current_user_has_permission('time_off.approve', 'all')
  and company_id = (
    select u.company_id::text
    from public.users u
    where u.id = private.resolve_uid()
  )
  and exists (
    select 1
    from public.users target
    where target.id::text = calendar_user_events.user_id
      and target.company_id::text = calendar_user_events.company_id
      and target.deleted_at is null
  )
  and (
    status <> 'approved'
    or (
      reviewed_by = private.resolve_uid()::text
      and reviewed_at is not null
    )
  )
);

drop policy if exists "Time off approvers update company events" on public.calendar_user_events;

create policy "Time off approvers update company events"
on public.calendar_user_events
for update
to public
using (
  type = 'time_off'
  and private.current_user_has_permission('time_off.approve', 'all')
  and company_id = (
    select u.company_id::text
    from public.users u
    where u.id = private.resolve_uid()
  )
)
with check (
  type = 'time_off'
  and private.current_user_has_permission('time_off.approve', 'all')
  and company_id = (
    select u.company_id::text
    from public.users u
    where u.id = private.resolve_uid()
  )
  and exists (
    select 1
    from public.users target
    where target.id::text = calendar_user_events.user_id
      and target.company_id::text = calendar_user_events.company_id
      and target.deleted_at is null
  )
);
