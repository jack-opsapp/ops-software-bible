-- Access telemetry for a feed token: last seen + a hit counter, so the
-- operator can tell whether their calendar app is actually polling.
-- Increment-in-place so concurrent polls cannot lose a count.
create or replace function public.touch_calendar_feed_token(p_token_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.calendar_feed_tokens
     set last_accessed_at = now(),
         access_count     = access_count + 1
   where id = p_token_id
     and revoked_at is null;
$$;

revoke all on function public.touch_calendar_feed_token(uuid) from public, anon, authenticated;
