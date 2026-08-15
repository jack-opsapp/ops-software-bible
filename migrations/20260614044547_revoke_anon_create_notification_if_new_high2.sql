-- HIGH-2: create_notification_if_new was anon+PUBLIC executable with fully
-- caller-controlled user_id/title/body/action_url — an unauthenticated client
-- could inject arbitrary (phishing) notifications into any user's rail.
--
-- Fix: REVOKE anon, PUBLIC. authenticated + service_role retain EXECUTE (the
-- web notification + inventory services call it from authenticated/server
-- contexts), and postgres retains it so the SECURITY DEFINER callers
-- (join_user_to_company etc., which run as the function owner) keep working.
REVOKE EXECUTE ON FUNCTION public.create_notification_if_new(text,text,text,text,text,boolean,text,text,text,text) FROM anon, PUBLIC;
