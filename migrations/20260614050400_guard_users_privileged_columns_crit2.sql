-- CRIT-2: any authenticated user could self-escalate via a direct PostgREST
-- UPDATE on public.users — the proven exploit was
--   UPDATE users SET role='owner', is_company_admin=true WHERE id = self
-- (user_self_update's WITH CHECK had no column restriction), and the permissive
-- company_isolation (cmd=ALL, PUBLIC) additionally let any member write OTHER
-- users' rows in their company.
--
-- Fix, two parts:
--  (1) A BEFORE UPDATE trigger that, for direct client sessions
--      (current_user = authenticated/anon), rejects any change to the
--      privilege-bearing columns is_company_admin / user_type / company_id, and
--      allows a change to the denormalized `role` label ONLY when the caller is a
--      company admin. The SECURITY DEFINER onboarding RPCs run as their owner
--      (current_user = postgres) and service_role server routes run as
--      service_role, so both remain the legitimate mutators of these columns and
--      are exempt. `role` stays client-writable for admins because it is purely a
--      denormalized label (RLS never authorizes off users.role — it authorizes
--      off is_company_admin / company_id / companies.admin_ids), and the live web
--      + iOS "assign role" flows write it directly; fully server-mediating role
--      assignment is tracked as a follow-up (see deliverable). The audit also
--      listed account_holder_id — that column does NOT exist on public.users
--      (it lives on companies), so it is intentionally omitted here.
--  (2) Scope the users company-isolation policy: split the old cmd=ALL/PUBLIC
--      policy into SELECT-for-all-members (peers must remain readable for team
--      lists / assignee names) and ALL-for-admins (only admins may write peer
--      rows). Self writes continue via user_self_update / user_self_insert.
--
-- The trigger function is SECURITY INVOKER on purpose: current_user must reflect
-- the live session role to tell a client write from a definer-RPC / service_role
-- write.

CREATE OR REPLACE FUNCTION public.guard_users_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  -- Trusted writers (the SECURITY DEFINER onboarding RPCs run as postgres;
  -- server routes run as service_role) are exempt; only direct client sessions
  -- are gated.
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.is_company_admin IS DISTINCT FROM OLD.is_company_admin THEN
    RAISE EXCEPTION 'is_company_admin cannot be changed by a client'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.user_type IS DISTINCT FROM OLD.user_type THEN
    RAISE EXCEPTION 'user_type cannot be changed by a client'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
    RAISE EXCEPTION 'company_id cannot be changed by a client; use join_user_to_company / create_company_for_owner'
      USING ERRCODE = '42501';
  END IF;

  -- role is a denormalized label, not an authorization source. Company admins
  -- may assign it (the live role-assignment flows); a non-admin (incl. a user
  -- trying to set their own role) is rejected.
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF NOT private.current_user_is_admin() THEN
      RAISE EXCEPTION 'role can only be changed by a company admin'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.guard_users_privileged_columns() TO authenticated, anon, service_role;

DROP TRIGGER IF EXISTS guard_users_privileged_columns_trg ON public.users;
CREATE TRIGGER guard_users_privileged_columns_trg
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_users_privileged_columns();

-- Scope company isolation: keep peer reads for all members, restrict peer writes
-- to admins.
DROP POLICY IF EXISTS company_isolation ON public.users;

CREATE POLICY users_company_select ON public.users
  FOR SELECT
  USING (company_id = (SELECT private.get_user_company_id()));

CREATE POLICY users_company_admin ON public.users
  FOR ALL
  USING (
    company_id = (SELECT private.get_user_company_id())
    AND (SELECT private.current_user_is_admin())
  )
  WITH CHECK (
    company_id = (SELECT private.get_user_company_id())
    AND (SELECT private.current_user_is_admin())
  );
