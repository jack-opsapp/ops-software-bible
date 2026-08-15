-- Phase 1 patch — change spec_internal_notes.created_by_user_id FK action
-- from ON DELETE SET NULL to ON DELETE RESTRICT.
--
-- The original migration (2026-05-26-06-spec-stage-f2b-internal-notes.sql)
-- declared the column NOT NULL and the FK ON DELETE SET NULL — these
-- contradict (Postgres allows table creation but user deletion fails with
-- FK violation if any internal_notes row references the deleted user).
--
-- Internal notes are audit records — operator deletion should be blocked
-- if notes exist (RESTRICT), not allowed-to-orphan (SET NULL or CASCADE).
-- This matches the semantic the column intends: created_by_user_id is
-- traceability metadata for an append-only operator-only revision log.

alter table public.spec_internal_notes
  drop constraint spec_internal_notes_created_by_user_id_fkey;

alter table public.spec_internal_notes
  add constraint spec_internal_notes_created_by_user_id_fkey
  foreign key (created_by_user_id)
  references public.users(id)
  on delete restrict;
