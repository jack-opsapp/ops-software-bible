-- Restore the mention-based view grant on private.current_user_can_view_project.
-- Migration 074 (074_mention_based_project_access) added an OR EXISTS(<live note
-- mentioning me>) branch so a mentioned-but-not-assigned user could VIEW a project.
-- A later projects-table-v2 RLS refactor re-CREATE-OR-REPLACE'd this helper into the
-- standardized "EXISTS(project) AND (admin OR all OR (assigned AND in_project))" shape
-- and silently dropped the mention branch — regressing Bug G9. This restores it within
-- the current structure. View-only: current_user_can_edit_project uses
-- current_user_in_project (not this helper), so mention grants never confer edit.
CREATE OR REPLACE FUNCTION private.current_user_can_view_project(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id = p_project_id
      AND p.deleted_at IS NULL
      AND p.company_id = (SELECT private.get_user_company_id())
  ) AND (
    private.current_user_is_admin()
    OR private.current_user_scope_for('projects.view') = 'all'
    OR (
      private.current_user_scope_for('projects.view') = 'assigned'
      AND (
        private.current_user_in_project(p_project_id)
        OR EXISTS (
          SELECT 1 FROM public.project_notes pn
          WHERE pn.project_id = p_project_id::text
            AND pn.deleted_at IS NULL
            AND private.get_current_user_id()::text = ANY (COALESCE(pn.mentioned_user_ids, ARRAY[]::text[]))
        )
      )
    )
  );
$function$;

COMMENT ON FUNCTION private.current_user_can_view_project(uuid) IS
  'Read-only access helper for the projects domain. Superset of current_user_in_project - adds mention-based grant from project_notes.mentioned_user_ids (Bug G9, 2026-04-20; restored 2026-06-04 after a projects-table-v2 refactor dropped it). MUST NOT be used in UPDATE/DELETE/INSERT policies; mention grants are view-only.';
