CREATE OR REPLACE FUNCTION private.get_current_user_id()
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT id FROM public.users
  WHERE email = (auth.jwt() ->> 'email')
    AND deleted_at IS NULL
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION private.current_user_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.companies c ON c.id = u.company_id
    WHERE u.email = (auth.jwt() ->> 'email')
      AND u.deleted_at IS NULL
      AND (
        COALESCE(u.is_company_admin, false)
        OR u.id::text = c.account_holder_id
        OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[]))
      )
  )
$$;

CREATE OR REPLACE FUNCTION private.current_user_scope_for(p_permission text)
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT rp.scope
  FROM public.user_roles ur
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  WHERE ur.user_id = private.get_current_user_id()::text
    AND rp.permission = p_permission
  ORDER BY CASE rp.scope
    WHEN 'all' THEN 1
    WHEN 'assigned' THEN 2
    WHEN 'own' THEN 3
    ELSE 4
  END
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION private.current_user_in_project(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id = p_project_id
      AND private.get_current_user_id()::text = ANY(COALESCE(p.team_member_ids, ARRAY[]::text[]))
  ) OR EXISTS (
    SELECT 1 FROM public.project_tasks pt
    WHERE pt.project_id = p_project_id
      AND private.get_current_user_id()::text = ANY(COALESCE(pt.team_member_ids, ARRAY[]::text[]))
  )
$$;

GRANT EXECUTE ON FUNCTION private.get_current_user_id() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.current_user_is_admin() TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.current_user_scope_for(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION private.current_user_in_project(uuid) TO PUBLIC;

DROP POLICY IF EXISTS role_scope_read ON public.projects;
CREATE POLICY role_scope_read ON public.projects
AS RESTRICTIVE
FOR SELECT
TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('projects.view')
      WHEN 'all' THEN true
      WHEN 'assigned' THEN
        private.get_current_user_id()::text = ANY(COALESCE(team_member_ids, ARRAY[]::text[]))
        OR EXISTS (
          SELECT 1 FROM public.project_tasks pt
          WHERE pt.project_id = projects.id
            AND private.get_current_user_id()::text = ANY(COALESCE(pt.team_member_ids, ARRAY[]::text[]))
        )
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_read ON public.project_tasks;
CREATE POLICY role_scope_read ON public.project_tasks
AS RESTRICTIVE
FOR SELECT
TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('tasks.view')
      WHEN 'all' THEN true
      WHEN 'assigned' THEN
        private.get_current_user_id()::text = ANY(COALESCE(project_tasks.team_member_ids, ARRAY[]::text[]))
        OR private.current_user_in_project(project_tasks.project_id)
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_read ON public.clients;
CREATE POLICY role_scope_read ON public.clients
AS RESTRICTIVE
FOR SELECT
TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('clients.view')
      WHEN 'all' THEN true
      WHEN 'assigned' THEN EXISTS (
        SELECT 1 FROM public.projects p
        WHERE p.client_id = clients.id
          AND private.get_current_user_id()::text = ANY(COALESCE(p.team_member_ids, ARRAY[]::text[]))
      )
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_read ON public.estimates;
CREATE POLICY role_scope_read ON public.estimates
AS RESTRICTIVE
FOR SELECT
TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('estimates.view')
      WHEN 'all' THEN true
      WHEN 'assigned' THEN
        project_id IS NOT NULL AND private.current_user_in_project(project_id::uuid)
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_read ON public.invoices;
CREATE POLICY role_scope_read ON public.invoices
AS RESTRICTIVE
FOR SELECT
TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('invoices.view')
      WHEN 'all' THEN true
      WHEN 'assigned' THEN
        project_id IS NOT NULL AND private.current_user_in_project(project_id)
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_read ON public.line_items;
CREATE POLICY role_scope_read ON public.line_items
AS RESTRICTIVE
FOR SELECT
TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    estimate_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.estimates e WHERE e.id = line_items.estimate_id
    )
  )
  OR (
    invoice_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.invoices i WHERE i.id = line_items.invoice_id
    )
  )
);

