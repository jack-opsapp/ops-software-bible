-- Spawned by: RLS HARDENING - P1-1
-- Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §13.1
-- Replaces wide-open policies created in 012_create_photo_annotations.sql with
-- company-scoped equivalents using private.get_user_company_id()::text
-- (canonical pattern; same form as deck_designs migration 050).
-- SELECT additionally enforces deleted_at IS NULL per spec §13.1.

DROP POLICY IF EXISTS "Users can read company annotations" ON public.project_photo_annotations;
DROP POLICY IF EXISTS "Users can create annotations"       ON public.project_photo_annotations;
DROP POLICY IF EXISTS "Users can update annotations"       ON public.project_photo_annotations;

CREATE POLICY "Users can read company annotations"
  ON public.project_photo_annotations
  FOR SELECT
  USING (
    company_id = (SELECT private.get_user_company_id())::text
    AND deleted_at IS NULL
  );

CREATE POLICY "Users can create annotations"
  ON public.project_photo_annotations
  FOR INSERT
  WITH CHECK (
    company_id = (SELECT private.get_user_company_id())::text
  );

CREATE POLICY "Users can update annotations"
  ON public.project_photo_annotations
  FOR UPDATE
  USING (
    company_id = (SELECT private.get_user_company_id())::text
  )
  WITH CHECK (
    company_id = (SELECT private.get_user_company_id())::text
  );
