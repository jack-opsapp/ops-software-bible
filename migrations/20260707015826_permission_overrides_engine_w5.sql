-- PERMISSION OVERRIDES ENGINE — BUG BURNDOWN W5 (2026-07-03)
-- Folds user_permission_overrides into server permission truth; adds Team read
-- policies; extends override admin to team.assign_roles; closes roles cross-tenant hole.

CREATE OR REPLACE FUNCTION public.has_permission(
  p_user_id        uuid,
  p_permission     text,
  p_required_scope text DEFAULT 'all'::text
) RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin         boolean;
  v_scope            text;
  v_override_granted boolean;
  v_override_scope   text;
  v_override_found   boolean := false;
BEGIN
  IF p_user_id IS NULL OR p_permission IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.companies c ON c.id = u.company_id
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
      AND (
        COALESCE(u.is_company_admin, false)
        OR u.id::text = c.account_holder_id
        OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[]))
      )
  ) INTO v_is_admin;

  IF v_is_admin THEN
    RETURN true;
  END IF;

  SELECT upo.granted, upo.scope, true
  INTO v_override_granted, v_override_scope, v_override_found
  FROM public.user_permission_overrides upo
  JOIN public.users u ON u.id = upo.user_id
  WHERE upo.user_id = p_user_id
    AND upo.permission = p_permission
    AND u.deleted_at IS NULL
    AND upo.company_id = u.company_id
  LIMIT 1;

  IF v_override_found THEN
    IF NOT v_override_granted THEN
      RETURN false;
    END IF;
    IF v_override_scope IS NOT NULL THEN
      IF v_override_scope = 'all' THEN RETURN true; END IF;
      IF v_override_scope = 'assigned' THEN
        RETURN p_required_scope IN ('assigned', 'own');
      END IF;
      IF v_override_scope = 'own' THEN
        RETURN p_required_scope = 'own';
      END IF;
      RETURN false;
    END IF;
  END IF;

  SELECT rp.scope
  INTO v_scope
  FROM public.user_roles ur
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  WHERE ur.user_id = p_user_id::text
    AND rp.permission = p_permission
  ORDER BY CASE rp.scope
    WHEN 'all'      THEN 1
    WHEN 'assigned' THEN 2
    WHEN 'own'      THEN 3
    ELSE                 4
  END
  LIMIT 1;

  IF v_scope IS NULL THEN
    RETURN false;
  END IF;

  IF v_scope = 'all' THEN
    RETURN true;
  END IF;
  IF v_scope = 'assigned' THEN
    RETURN p_required_scope IN ('assigned', 'own');
  END IF;
  IF v_scope = 'own' THEN
    RETURN p_required_scope = 'own';
  END IF;

  RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION private.current_user_scope_for(p_permission text)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (
    SELECT private.get_current_user_id() AS id,
           private.get_user_company_id() AS company_id
  ),
  o AS (
    SELECT upo.granted, upo.scope
    FROM me
    JOIN public.user_permission_overrides upo
      ON upo.user_id = me.id
     AND upo.permission = p_permission
     AND upo.company_id = me.company_id
    LIMIT 1
  ),
  r AS (
    SELECT rp.scope
    FROM me
    JOIN public.user_roles ur ON ur.user_id = me.id::text
    JOIN public.role_permissions rp
      ON rp.role_id = ur.role_id
     AND rp.permission = p_permission
    ORDER BY CASE rp.scope
      WHEN 'all'      THEN 1
      WHEN 'assigned' THEN 2
      WHEN 'own'      THEN 3
      ELSE                 4
    END
    LIMIT 1
  )
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM o WHERE NOT granted)                    THEN NULL
    WHEN EXISTS (SELECT 1 FROM o WHERE granted AND scope IS NOT NULL)  THEN (SELECT scope FROM o)
    ELSE                                                                    (SELECT scope FROM r)
  END;
$function$;

DROP POLICY IF EXISTS "company members read company role assignments" ON public.user_roles;
CREATE POLICY "company members read company role assignments"
ON public.user_roles
FOR SELECT
TO public
USING (
  user_id IN (
    SELECT u.id::text
    FROM public.users u
    WHERE u.company_id = (SELECT private.get_user_company_id())
      AND u.deleted_at IS NULL
  )
);

DROP POLICY IF EXISTS "company members read visible role permissions" ON public.role_permissions;
CREATE POLICY "company members read visible role permissions"
ON public.role_permissions
FOR SELECT
TO public
USING (
  role_id IN (
    SELECT r.id
    FROM public.roles r
    WHERE r.is_preset = true
       OR r.company_id = (SELECT private.get_user_company_id())
  )
);

DROP POLICY IF EXISTS "Admins can read company overrides" ON public.user_permission_overrides;
CREATE POLICY "Access managers read company overrides"
ON public.user_permission_overrides
FOR SELECT
TO public
USING (
  (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
  AND company_id = (SELECT private.get_user_company_id())
);

DROP POLICY IF EXISTS "Admins can insert company overrides" ON public.user_permission_overrides;
CREATE POLICY "Access managers insert company overrides"
ON public.user_permission_overrides
FOR INSERT
TO public
WITH CHECK (
  (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
  AND company_id = (SELECT private.get_user_company_id())
);

DROP POLICY IF EXISTS "Admins can update company overrides" ON public.user_permission_overrides;
CREATE POLICY "Access managers update company overrides"
ON public.user_permission_overrides
FOR UPDATE
TO public
USING (
  (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
  AND company_id = (SELECT private.get_user_company_id())
)
WITH CHECK (
  (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
  AND company_id = (SELECT private.get_user_company_id())
);

DROP POLICY IF EXISTS "Admins can delete company overrides" ON public.user_permission_overrides;
CREATE POLICY "Access managers delete company overrides"
ON public.user_permission_overrides
FOR DELETE
TO public
USING (
  (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
  AND company_id = (SELECT private.get_user_company_id())
);

DROP POLICY IF EXISTS roles_select ON public.roles;
CREATE POLICY roles_select
ON public.roles
FOR SELECT
TO public
USING (
  is_preset = true
  OR company_id = (SELECT private.get_user_company_id())
);

DROP POLICY IF EXISTS roles_insert ON public.roles;
CREATE POLICY roles_insert
ON public.roles
FOR INSERT
TO public
WITH CHECK (
  is_preset = false
  AND company_id = (SELECT private.get_user_company_id())
  AND (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
);

DROP POLICY IF EXISTS roles_update ON public.roles;
CREATE POLICY roles_update
ON public.roles
FOR UPDATE
TO public
USING (
  is_preset = false
  AND company_id = (SELECT private.get_user_company_id())
  AND (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
)
WITH CHECK (
  is_preset = false
  AND company_id = (SELECT private.get_user_company_id())
);

DROP POLICY IF EXISTS roles_delete ON public.roles;
CREATE POLICY roles_delete
ON public.roles
FOR DELETE
TO public
USING (
  is_preset = false
  AND company_id = (SELECT private.get_user_company_id())
  AND (private.current_user_is_admin()
    OR private.current_user_has_permission('team.assign_roles', 'all'))
);
