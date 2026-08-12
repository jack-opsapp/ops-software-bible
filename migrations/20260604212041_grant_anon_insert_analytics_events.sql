-- analytics_events :: allow the Firebase-bridged client roles (iOS + web) to
-- append events. Clients reach PostgREST as the `anon` role (Firebase JWT bridge,
-- auth.uid() NULL); legacy migration 048 granted only `authenticated`, so iOS
-- appends were rejected 42501 ~every 30s. iOS uses
--   .upsert(onConflict:"id", ignoreDuplicates:true) => INSERT ... ON CONFLICT DO NOTHING
-- with return=minimal, so INSERT is the only privilege required. Reads stay
-- service-role / ops-admin only. Mirrors the onboarding_analytics sink pattern.

grant insert on table public.analytics_events to anon, authenticated;

revoke select, update, delete on table public.analytics_events from anon;

drop policy if exists "analytics_events_client_insert" on public.analytics_events;
create policy "analytics_events_client_insert"
on public.analytics_events
for insert
to anon, authenticated
with check (true);
