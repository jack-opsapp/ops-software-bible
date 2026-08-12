-- Migration 074: Mention-based project access (Bug G9)
BEGIN;

CREATE OR REPLACE FUNCTION private.current_user_can_view_project(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT private.current_user_in_project(p_project_id)
      OR EXISTS (
        SELECT 1 FROM public.project_notes pn
        WHERE pn.project_id = p_project_id::text
          AND pn.deleted_at IS NULL
          AND private.get_current_user_id()::text = ANY(COALESCE(pn.mentioned_user_ids, ARRAY[]::text[]))
      );
$function$;

COMMENT ON FUNCTION private.current_user_can_view_project(uuid) IS
  'Read-only access helper for the projects domain. Superset of current_user_in_project - adds mention-based grant from project_notes.mentioned_user_ids (Bug G9, 2026-04-20). MUST NOT be used in UPDATE/DELETE/INSERT policies; mention grants are view-only.';

DROP POLICY IF EXISTS role_scope_read ON public.projects;
CREATE POLICY role_scope_read ON public.projects
FOR SELECT
USING (
  private.current_user_is_admin() OR
  CASE private.current_user_scope_for('projects.view')
    WHEN 'all' THEN true
    WHEN 'assigned' THEN private.current_user_can_view_project(projects.id)
    ELSE false
  END
);

DROP POLICY IF EXISTS role_scope_read ON public.project_tasks;
CREATE POLICY role_scope_read ON public.project_tasks
FOR SELECT
USING (
  private.current_user_is_admin() OR
  CASE private.current_user_scope_for('tasks.view')
    WHEN 'all' THEN true
    WHEN 'assigned' THEN (
      (private.get_current_user_id()::text = ANY (COALESCE(team_member_ids, ARRAY[]::text[])))
      OR private.current_user_can_view_project(project_id)
    )
    ELSE false
  END
);

COMMIT;
