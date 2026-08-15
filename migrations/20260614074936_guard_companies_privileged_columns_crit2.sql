-- ============================================================================
-- CRIT-2 follow-up: close the privilege-escalation hole on public.companies.
--
-- Hole: RLS policy `company_self_access` was FOR ALL to PUBLIC with
--   USING (id = private.get_user_company_id()), no admin gate and no WITH CHECK,
--   so ANY authenticated company member could UPDATE their companies row —
--   including admin_ids (self-add -> private.current_user_is_admin() returns true,
--   defeating the CRIT-2 users guard) and every billing/seat/entitlement column.
--   Verified live: a non-admin member could UPDATE admin_ids and subscription_status.
--
-- Fix mirrors guard_users_privileged_columns_crit2:
--   1. Split company_self_access into member-SELECT + admin-only write
--      (parallel to users_company_select + users_company_admin).
--   2. BEFORE UPDATE trigger blocking client writes to escalation/billing columns
--      for the authenticated/anon roles ONLY. Trusted writers stay exempt — the
--      SECURITY DEFINER onboarding RPCs (create_company_for_owner,
--      join_user_to_company) run as postgres; the ops-web Stripe routes/webhook
--      and billing crons run as service_role.
--
-- Blast radius verified (ops-ios + OPS-Web): the only legitimate authenticated
-- client write to a guarded column is seated_employee_ids (seat management), done
-- exclusively by admins (all 53 seat-managers in prod satisfy current_user_is_admin);
-- it is therefore allowed for admins and blocked for non-admins. The iOS
-- subscription_status='expired' trial self-heal is a fire-and-forget cosmetic write;
-- both clients compute trial lockout from trial_end_date, so blocking it changes no
-- user-facing behavior.
-- ============================================================================

-- 1. RLS split -------------------------------------------------------------
DROP POLICY IF EXISTS company_self_access  ON public.companies;
DROP POLICY IF EXISTS company_member_select ON public.companies;
DROP POLICY IF EXISTS company_admin_write   ON public.companies;

-- Members may READ their own company (replaces the SELECT half of the old FOR ALL policy;
-- the creator-scoped company_select_for_creator policy remains for the onboarding window).
CREATE POLICY company_member_select ON public.companies
  FOR SELECT
  USING (id = (SELECT private.get_user_company_id()));

-- Only company admins may WRITE (INSERT/UPDATE/DELETE) their own company.
CREATE POLICY company_admin_write ON public.companies
  FOR ALL
  USING (
    id = (SELECT private.get_user_company_id())
    AND (SELECT private.current_user_is_admin())
  )
  WITH CHECK (
    id = (SELECT private.get_user_company_id())
    AND (SELECT private.current_user_is_admin())
  );

-- 2. Defense-in-depth column guard ----------------------------------------
CREATE OR REPLACE FUNCTION public.guard_companies_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $func$
BEGIN
  -- Trusted writers are exempt: the SECURITY DEFINER onboarding RPCs run as
  -- postgres; the ops-web Stripe routes / webhook / billing crons run as
  -- service_role. Only direct client sessions (authenticated/anon) are gated.
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  -- Privilege keys. admin_ids / account_holder_id both feed
  -- private.current_user_is_admin(); a client-writable value is the escalation
  -- vector this migration closes. No client writes them (the role model lives on
  -- users/user_roles; both columns are seeded only by the onboarding RPC).
  IF NEW.admin_ids IS DISTINCT FROM OLD.admin_ids THEN
    RAISE EXCEPTION 'admin_ids cannot be changed by a client' USING ERRCODE = '42501';
  END IF;
  IF NEW.account_holder_id IS DISTINCT FROM OLD.account_holder_id THEN
    RAISE EXCEPTION 'account_holder_id cannot be changed by a client' USING ERRCODE = '42501';
  END IF;

  -- Billing / subscription / entitlement keys — written ONLY by service_role
  -- (Stripe webhook, /api/stripe/*, reconcile + expire-grace crons) or the OPS
  -- platform-admin console. A client-writable value is a paywall / billing bypass.
  IF NEW.max_seats             IS DISTINCT FROM OLD.max_seats             THEN RAISE EXCEPTION 'max_seats cannot be changed by a client'             USING ERRCODE = '42501'; END IF;
  IF NEW.subscription_status   IS DISTINCT FROM OLD.subscription_status   THEN RAISE EXCEPTION 'subscription_status cannot be changed by a client'   USING ERRCODE = '42501'; END IF;
  IF NEW.subscription_plan     IS DISTINCT FROM OLD.subscription_plan     THEN RAISE EXCEPTION 'subscription_plan cannot be changed by a client'     USING ERRCODE = '42501'; END IF;
  IF NEW.subscription_end      IS DISTINCT FROM OLD.subscription_end      THEN RAISE EXCEPTION 'subscription_end cannot be changed by a client'      USING ERRCODE = '42501'; END IF;
  IF NEW.subscription_period   IS DISTINCT FROM OLD.subscription_period   THEN RAISE EXCEPTION 'subscription_period cannot be changed by a client'   USING ERRCODE = '42501'; END IF;
  IF NEW.subscription_ids_json IS DISTINCT FROM OLD.subscription_ids_json THEN RAISE EXCEPTION 'subscription_ids_json cannot be changed by a client' USING ERRCODE = '42501'; END IF;
  IF NEW.trial_start_date      IS DISTINCT FROM OLD.trial_start_date      THEN RAISE EXCEPTION 'trial_start_date cannot be changed by a client'      USING ERRCODE = '42501'; END IF;
  IF NEW.trial_end_date        IS DISTINCT FROM OLD.trial_end_date        THEN RAISE EXCEPTION 'trial_end_date cannot be changed by a client'        USING ERRCODE = '42501'; END IF;
  IF NEW.seat_grace_start_date IS DISTINCT FROM OLD.seat_grace_start_date THEN RAISE EXCEPTION 'seat_grace_start_date cannot be changed by a client' USING ERRCODE = '42501'; END IF;
  IF NEW.has_priority_support  IS DISTINCT FROM OLD.has_priority_support  THEN RAISE EXCEPTION 'has_priority_support cannot be changed by a client'  USING ERRCODE = '42501'; END IF;
  IF NEW.priority_support_period IS DISTINCT FROM OLD.priority_support_period THEN RAISE EXCEPTION 'priority_support_period cannot be changed by a client' USING ERRCODE = '42501'; END IF;
  IF NEW.data_setup_purchased  IS DISTINCT FROM OLD.data_setup_purchased  THEN RAISE EXCEPTION 'data_setup_purchased cannot be changed by a client'  USING ERRCODE = '42501'; END IF;
  IF NEW.data_setup_completed  IS DISTINCT FROM OLD.data_setup_completed  THEN RAISE EXCEPTION 'data_setup_completed cannot be changed by a client'  USING ERRCODE = '42501'; END IF;
  IF NEW.data_setup_scheduled  IS DISTINCT FROM OLD.data_setup_scheduled  THEN RAISE EXCEPTION 'data_setup_scheduled cannot be changed by a client'  USING ERRCODE = '42501'; END IF;
  IF NEW.stripe_customer_id    IS DISTINCT FROM OLD.stripe_customer_id    THEN RAISE EXCEPTION 'stripe_customer_id cannot be changed by a client'    USING ERRCODE = '42501'; END IF;

  -- Company join code — minted only at creation (onboarding RPC). A client-writable
  -- code lets a member rotate it (breaking pending joins) or squat another company's code.
  IF NEW.company_code IS DISTINCT FROM OLD.company_code THEN
    RAISE EXCEPTION 'company_code cannot be changed by a client' USING ERRCODE = '42501';
  END IF;

  -- Seat roster — admins legitimately manage seats directly from the client
  -- (iOS addSeat/removeSeat gated settings.billing; web team-tab gated team.manage;
  -- every seat-manager in prod satisfies current_user_is_admin()). A non-admin must
  -- not touch the roster (belt-and-suspenders behind the admin-only write policy).
  IF NEW.seated_employee_ids IS DISTINCT FROM OLD.seated_employee_ids THEN
    IF NOT (SELECT private.current_user_is_admin()) THEN
      RAISE EXCEPTION 'seated_employee_ids can only be changed by a company admin' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS guard_companies_privileged_columns_trg ON public.companies;
CREATE TRIGGER guard_companies_privileged_columns_trg
  BEFORE UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.guard_companies_privileged_columns();
