-- Applied to prod ijeekuhbatykdomumfjx 2026-07-29 (SYSTEMS REPAIR W1-4; bug 1154fe67).
-- Photo permissions per the operator's decided policy (2026-07-29, P3 findings §3):
--   * crews CAN toggle client visibility (and caption) on ANY company photo
--   * crews CAN soft-delete their OWN photos only (uploaded_by = requester)
--   * admin paths delete any; hard DELETE stays denied (RESTRICTIVE policy untouched)
-- anon/authenticated previously had INSERT,SELECT only -> every iOS UPDATE failed 42501
-- (soft-deletes at ProjectNotesViewModel.swift:592-597 + ImageSyncManager.swift:850-867,
-- visibility at ImageSyncManager.swift:388-399). Evidence: 0/826 rows ever client-visible;
-- iOS deletes resurface on the next pull.
--
-- Grant is column-scoped: clients can touch ONLY these three columns.
GRANT UPDATE (deleted_at, is_client_visible, caption) ON public.project_photos TO anon, authenticated;

-- Field-level rules live in the write-guard below. The legacy RESTRICTIVE UPDATE policy
-- required private.current_user_can_edit_project(), which every real crew lacks
-- (verified 2026-07-29: all non-admin users in prod have NULL projects.edit scope) — keeping
-- it would nullify the decided company-wide visibility toggle. Tenancy stays enforced by the
-- PERMISSIVE company_isolation policy (its USING doubles as WITH CHECK for ALL policies).
DROP POLICY "project table photos update requires project edit" ON public.project_photos;

-- Write-guard (repo trg_*_00_write_guard pattern): fires for client roles only; service
-- paths (web admin routes run service_role) and migrations pass untouched.
-- uploaded_by is text and legacy iOS rows carry UPPERCASE UUIDs -> compare lowercased.
CREATE OR REPLACE FUNCTION public.project_photos_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid;
BEGIN
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
    v_uid := private.resolve_uid();
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'project_photos: soft-delete requires a resolvable user'
        USING ERRCODE = '42501';
    END IF;
    IF lower(OLD.uploaded_by) <> lower(v_uid::text)
       AND NOT private.current_user_has_permission('projects.edit', 'all') THEN
      RAISE EXCEPTION 'project_photos: soft-delete allowed on own photos only'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_project_photos_00_write_guard ON public.project_photos;
CREATE TRIGGER trg_project_photos_00_write_guard
  BEFORE UPDATE ON public.project_photos
  FOR EACH ROW EXECUTE FUNCTION public.project_photos_write_guard();
