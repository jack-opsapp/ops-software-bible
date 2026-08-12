-- CRIT-3 Phase D / MED-3 — sub-resolving company-setup RPC. Replaces the
-- email-resolvable service_role is_company_admin/company_id elevation in
-- /api/setup/progress. Resolves the caller from the JWT sub ONLY, authorizes
-- owner/admin (also blocking joined-member self-elevation), and writes only the
-- caller's own row + company. Additive: nothing calls it until the OPS-Web web
-- code deploys with CRIT3_SUB_IDENTITY=true. Safe if called directly (a user can
-- only set up their own company). Grants match create_company_for_owner.
CREATE OR REPLACE FUNCTION public.update_company_setup_for_member(
  p_name text,
  p_industries text[],
  p_company_size text,
  p_company_age text,
  p_weather_dependent boolean
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_user public.users%rowtype;
  v_company public.companies%rowtype;
BEGIN
  IF v_sub IS NULL OR v_sub = '' THEN
    RAISE EXCEPTION 'NO_JWT';
  END IF;

  SELECT * INTO v_user FROM public.users
  WHERE (auth_id = v_sub OR firebase_uid = v_sub) AND deleted_at IS NULL
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_USER_ROW';
  END IF;

  IF v_user.company_id IS NULL THEN
    RAISE EXCEPTION 'NO_COMPANY';
  END IF;

  SELECT * INTO v_company FROM public.companies
  WHERE id = v_user.company_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_COMPANY';
  END IF;

  IF NOT (
    COALESCE(v_user.is_company_admin, false)
    OR v_user.id::text = v_company.account_holder_id
    OR v_user.id::text = ANY(COALESCE(v_company.admin_ids, ARRAY[]::text[]))
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  UPDATE public.companies SET
    name = COALESCE(NULLIF(p_name, ''), name),
    industries = CASE WHEN p_industries IS NOT NULL AND array_length(p_industries, 1) IS NOT NULL
                      THEN p_industries ELSE industries END,
    company_size = COALESCE(p_company_size, company_size),
    company_age = COALESCE(p_company_age, company_age),
    weather_dependent = COALESCE(p_weather_dependent, weather_dependent),
    updated_at = now()
  WHERE id = v_user.company_id;

  UPDATE public.users SET is_company_admin = true, updated_at = now()
  WHERE id = v_user.id;

  PERFORM public.initialize_company_defaults(v_user.company_id);

  RETURN v_user.company_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.update_company_setup_for_member(text, text[], text, text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.update_company_setup_for_member(text, text[], text, text, boolean) TO authenticated, service_role;
