-- project_photos_client_update_grant
--
-- Bug 1154fe67 (iOS bug sweep 2026-08-28, Cluster D): widens the column-scoped
-- client UPDATE grant on public.project_photos from the three columns granted by
-- ledger 20260729162950 (deleted_at, is_client_visible, caption) to include the
-- three capture-metadata columns the iOS sync reconciler needs.
--
-- Live state read 2026-08-29 (information_schema.column_privileges): anon and
-- authenticated already hold UPDATE on (deleted_at, is_client_visible, caption)
-- and no other column. NOTE for anyone reading the bug thread: the sweep's
-- planning probe used information_schema.role_table_grants, which reports only
-- TABLE-level grants and is blind to column-scoped ones -- hence the earlier
-- claim that anon/authenticated held INSERT,SELECT only. This migration is
-- therefore additive over an already-working delete/visibility path, not the
-- restoration of one. GRANT is idempotent, so re-granting the original three is
-- a no-op and keeps the end state stated in one place.
--
-- Row-level rules are ALREADY enforced and unchanged:
--   * RLS company_isolation (PERMISSIVE ALL, roles {public}) row-gates UPDATE by company.
--   * trg_project_photos_00_write_guard (public.project_photos_write_guard) enforces
--     Jackson's 2026-07-29 decision: deleted_at changes require uploader-self
--     (case-insensitive) OR projects.edit at scope 'all' (admins fold in);
--     is_client_visible and caption stay company-wide.
--   * RESTRICTIVE "project table photos delete denied" keeps hard DELETE impossible.
--   * update_project_photos_timestamp maintains updated_at server-side.
--
-- Column scoping is the containment: url/project_id/company_id/uploaded_by/source/id
-- remain non-updatable by client roles. taken_at/thumbnail_url/rendered_url are granted
-- so the iOS sync reconciler (bug ba75732a) can heal the metadata-poor rows created by
-- private.execute_opportunity_conversion_core (which mirrors site-visit photos with
-- taken_at NULL and no thumbnails). 214 of 931 rows currently carry taken_at IS NULL.
--
-- Additive-only: safe for all shipped iOS builds.

grant update (deleted_at, is_client_visible, caption, taken_at, thumbnail_url, rendered_url)
  on table public.project_photos
  to anon, authenticated;
