-- Role-based RLS helpers + restrictive INSERT/UPDATE/DELETE policies
-- Complements the read scoping migration with write-path enforcement.

-- Reusable predicate: current user has a permission with AT LEAST the given scope.
-- Scope hierarchy: all > assigned > own. Admins bypass all checks.
CREATE OR REPLACE FUNCTION private.current_user_has_permission(
  p_permission text,
  p_min_scope text DEFAULT 'own'
)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_scope text;
BEGIN
  IF private.current_user_is_admin() THEN
    RETURN true;
  END IF;
  v_scope := private.current_user_scope_for(p_permission);
  IF v_scope IS NULL THEN
    RETURN false;
  END IF;
  IF v_scope = 'all' THEN RETURN true; END IF;
  IF v_scope = 'assigned' THEN
    RETURN p_min_scope IN ('assigned','own');
  END IF;
  IF v_scope = 'own' THEN
    RETURN p_min_scope = 'own';
  END IF;
  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION private.current_user_has_permission(text, text) TO PUBLIC;

-- ─── projects ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS role_scope_insert ON public.projects;
CREATE POLICY role_scope_insert ON public.projects
AS RESTRICTIVE FOR INSERT TO PUBLIC
WITH CHECK (private.current_user_has_permission('projects.create', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.projects;
CREATE POLICY role_scope_update ON public.projects
AS RESTRICTIVE FOR UPDATE TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('projects.edit')
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

DROP POLICY IF EXISTS role_scope_delete ON public.projects;
CREATE POLICY role_scope_delete ON public.projects
AS RESTRICTIVE FOR DELETE TO PUBLIC
USING (private.current_user_has_permission('projects.delete', 'all'));

-- ─── project_tasks ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS role_scope_insert ON public.project_tasks;
CREATE POLICY role_scope_insert ON public.project_tasks
AS RESTRICTIVE FOR INSERT TO PUBLIC
WITH CHECK (private.current_user_has_permission('tasks.create', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.project_tasks;
CREATE POLICY role_scope_update ON public.project_tasks
AS RESTRICTIVE FOR UPDATE TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('tasks.edit')
      WHEN 'all' THEN true
      WHEN 'assigned' THEN
        private.get_current_user_id()::text = ANY(COALESCE(project_tasks.team_member_ids, ARRAY[]::text[]))
        OR private.current_user_in_project(project_tasks.project_id)
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_delete ON public.project_tasks;
CREATE POLICY role_scope_delete ON public.project_tasks
AS RESTRICTIVE FOR DELETE TO PUBLIC
USING (private.current_user_has_permission('tasks.delete', 'all'));

-- ─── clients ─────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS role_scope_insert ON public.clients;
CREATE POLICY role_scope_insert ON public.clients
AS RESTRICTIVE FOR INSERT TO PUBLIC
WITH CHECK (private.current_user_has_permission('clients.create', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.clients;
CREATE POLICY role_scope_update ON public.clients
AS RESTRICTIVE FOR UPDATE TO PUBLIC
USING (private.current_user_has_permission('clients.edit', 'all'));

DROP POLICY IF EXISTS role_scope_delete ON public.clients;
CREATE POLICY role_scope_delete ON public.clients
AS RESTRICTIVE FOR DELETE TO PUBLIC
USING (private.current_user_has_permission('clients.delete', 'all'));

-- ─── estimates ───────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS role_scope_insert ON public.estimates;
CREATE POLICY role_scope_insert ON public.estimates
AS RESTRICTIVE FOR INSERT TO PUBLIC
WITH CHECK (private.current_user_has_permission('estimates.create', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.estimates;
CREATE POLICY role_scope_update ON public.estimates
AS RESTRICTIVE FOR UPDATE TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (
    CASE private.current_user_scope_for('estimates.edit')
      WHEN 'all' THEN true
      WHEN 'own' THEN private.get_current_user_id() = created_by
      WHEN 'assigned' THEN
        project_id IS NOT NULL AND private.current_user_in_project(project_id::uuid)
      ELSE false
    END
  )
);

DROP POLICY IF EXISTS role_scope_delete ON public.estimates;
CREATE POLICY role_scope_delete ON public.estimates
AS RESTRICTIVE FOR DELETE TO PUBLIC
USING (private.current_user_has_permission('estimates.delete', 'all'));

-- ─── invoices ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS role_scope_insert ON public.invoices;
CREATE POLICY role_scope_insert ON public.invoices
AS RESTRICTIVE FOR INSERT TO PUBLIC
WITH CHECK (private.current_user_has_permission('invoices.create', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.invoices;
CREATE POLICY role_scope_update ON public.invoices
AS RESTRICTIVE FOR UPDATE TO PUBLIC
USING (private.current_user_has_permission('invoices.edit', 'all'));

DROP POLICY IF EXISTS role_scope_delete ON public.invoices;
CREATE POLICY role_scope_delete ON public.invoices
AS RESTRICTIVE FOR DELETE TO PUBLIC
USING (private.current_user_has_permission('invoices.delete', 'all'));

-- ─── line_items ──────────────────────────────────────────────────────────────
-- Writes require permission on the parent estimate or invoice. The admin
-- bypass in current_user_has_permission covers admin writes.
DROP POLICY IF EXISTS role_scope_insert ON public.line_items;
CREATE POLICY role_scope_insert ON public.line_items
AS RESTRICTIVE FOR INSERT TO PUBLIC
WITH CHECK (
  private.current_user_is_admin()
  OR (estimate_id IS NOT NULL AND private.current_user_has_permission('estimates.edit', 'own'))
  OR (invoice_id IS NOT NULL AND private.current_user_has_permission('invoices.edit', 'own'))
);

DROP POLICY IF EXISTS role_scope_update ON public.line_items;
CREATE POLICY role_scope_update ON public.line_items
AS RESTRICTIVE FOR UPDATE TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (estimate_id IS NOT NULL AND private.current_user_has_permission('estimates.edit', 'own'))
  OR (invoice_id IS NOT NULL AND private.current_user_has_permission('invoices.edit', 'own'))
);

DROP POLICY IF EXISTS role_scope_delete ON public.line_items;
CREATE POLICY role_scope_delete ON public.line_items
AS RESTRICTIVE FOR DELETE TO PUBLIC
USING (
  private.current_user_is_admin()
  OR (estimate_id IS NOT NULL AND private.current_user_has_permission('estimates.edit', 'own'))
  OR (invoice_id IS NOT NULL AND private.current_user_has_permission('invoices.edit', 'own'))
);

