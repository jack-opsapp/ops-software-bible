-- Allow unauthenticated read of app_messages so the force-update kill-switch
-- can wall the app even when a blocker bug breaks login/sync. Content is
-- non-sensitive broadcast/update copy (no customer or company data). Writes
-- remain service-role only (no INSERT/UPDATE/DELETE policy exists).
drop policy if exists "Authenticated users can view app_messages" on public.app_messages;
create policy "Anyone can view app_messages"
  on public.app_messages for select
  to anon, authenticated
  using (true);
