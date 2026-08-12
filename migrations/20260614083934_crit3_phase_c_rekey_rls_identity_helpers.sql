-- CRIT-3 Phase C — re-key the 5 RLS identity helpers off the cryptographic JWT
-- sub (auth_id/firebase_uid) instead of the spoofable email claim. All 296
-- dependent objects (228 policies + 58 functions + 1 view + 9 triggers) resolve
-- through these 5 bodies, so this CREATE OR REPLACE closes the account-takeover
-- vector with zero policy DDL. Gate satisfied 2026-06-14: every Firebase account
-- is sub-linked (backfill B=0/collisions=0); remaining unlinked rows are dormant
-- accounts with no Firebase login. Rollback (restore email bodies) staged in
-- docs/superpowers/migrations/2026-06-14-crit3-phase-c-rekey-rls-helpers.sql.

CREATE OR REPLACE FUNCTION private.resolve_uid()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION private.get_current_user_id()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION private.get_user_company_id()
 RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT company_id FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND company_id IS NOT NULL
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION public.get_user_company_id()
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT company_id::text FROM public.users
  WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))
    AND company_id IS NOT NULL
    AND deleted_at IS NULL
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION private.current_user_is_admin()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.companies c ON c.id = u.company_id
    WHERE (u.auth_id = (auth.jwt() ->> 'sub') OR u.firebase_uid = (auth.jwt() ->> 'sub'))
      AND u.deleted_at IS NULL
      AND (
        COALESCE(u.is_company_admin, false)
        OR u.id::text = c.account_holder_id
        OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[]))
      )
  )
$function$;
