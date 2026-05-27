-- 2026-05-26-08-spec-internal-notes-fk-fix.sql
--
-- Phase 1 patch — change spec_internal_notes.created_by_user_id FK action
-- from ON DELETE SET NULL to ON DELETE RESTRICT. Mirror of the migration
-- applied to ops-app (project ref: ijeekuhbatykdomumfjx) on 2026-05-27.
--
-- The original migration (2026-05-26-06-spec-stage-f2b-internal-notes.sql)
-- declared the column NOT NULL and the FK ON DELETE SET NULL — these
-- contradict. Postgres allows the table to exist, but if a user with
-- internal_notes rows is ever deleted, the FK action attempts to set the
-- column to NULL and the deletion fails with FK violation.
--
-- The correct semantic for an audit record is RESTRICT: block operator
-- deletion if internal_notes exist. The operator (or a future cleanup
-- script) must either delete the notes first or accept that the audit
-- trail prevents the deletion. SET NULL would orphan the audit trail;
-- CASCADE would destroy it — neither is right for traceability metadata
-- on an append-only operator-only revision log.

alter table public.spec_internal_notes
  drop constraint spec_internal_notes_created_by_user_id_fkey;

alter table public.spec_internal_notes
  add constraint spec_internal_notes_created_by_user_id_fkey
  foreign key (created_by_user_id)
  references public.users(id)
  on delete restrict;
