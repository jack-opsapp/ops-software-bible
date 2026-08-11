-- Hygiene: enqueue_google_calendar_sync() is a trigger function — it only ever
-- runs via trg_site_visits_google_calendar_sync (trigger firing does not consult
-- EXECUTE privilege). It was created with the default PUBLIC execute grant;
-- revoke it so the security advisor stops flagging an anon-executable
-- SECURITY DEFINER function. No behavior change.
revoke all on function public.enqueue_google_calendar_sync() from public, anon, authenticated, service_role;
