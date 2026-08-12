-- leads-review C-7: gate writes to the pipeline-owned tables on pipeline.manage,
-- mirroring the projects/clients role_scope_* pattern. SELECT stays governed by
-- company_isolation (+ the existing role_scope_read on opportunities). activities
-- and follow_ups are intentionally excluded (shared tables). Adds insert/update/
-- delete only — does not touch the existing role_scope_read policy.

-- opportunities -------------------------------------------------------------
DROP POLICY IF EXISTS role_scope_insert ON public.opportunities;
CREATE POLICY role_scope_insert ON public.opportunities
  AS RESTRICTIVE FOR INSERT TO public
  WITH CHECK (private.current_user_has_permission('pipeline.manage', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.opportunities;
CREATE POLICY role_scope_update ON public.opportunities
  AS RESTRICTIVE FOR UPDATE TO public
  USING      (private.current_user_has_permission('pipeline.manage', 'all'))
  WITH CHECK (private.current_user_has_permission('pipeline.manage', 'all'));

DROP POLICY IF EXISTS role_scope_delete ON public.opportunities;
CREATE POLICY role_scope_delete ON public.opportunities
  AS RESTRICTIVE FOR DELETE TO public
  USING (private.current_user_has_permission('pipeline.manage', 'all'));

-- stage_transitions (append-only audit log) ---------------------------------
DROP POLICY IF EXISTS role_scope_insert ON public.stage_transitions;
CREATE POLICY role_scope_insert ON public.stage_transitions
  AS RESTRICTIVE FOR INSERT TO public
  WITH CHECK (private.current_user_has_permission('pipeline.manage', 'all'));

DROP POLICY IF EXISTS role_scope_update ON public.stage_transitions;
CREATE POLICY role_scope_update ON public.stage_transitions
  AS RESTRICTIVE FOR UPDATE TO public
  USING      (private.current_user_has_permission('pipeline.manage', 'all'))
  WITH CHECK (private.current_user_has_permission('pipeline.manage', 'all'));

DROP POLICY IF EXISTS role_scope_delete ON public.stage_transitions;
CREATE POLICY role_scope_delete ON public.stage_transitions
  AS RESTRICTIVE FOR DELETE TO public
  USING (private.current_user_has_permission('pipeline.manage', 'all'));
