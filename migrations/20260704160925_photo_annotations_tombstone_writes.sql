-- Fix: soft-delete of photo annotations was impossible for ALL clients since
-- 2026-05-12 (bugs 452bab04/0415504f). Postgres applies SELECT policies as WITH
-- CHECK against the NEW row of any UPDATE that reads the table, so the SELECT
-- policy's `deleted_at IS NULL` clause rejected every tombstone write with 42501.
-- Company scoping stays; the tombstone-hiding clause (a UX filter, not a security
-- boundary) moves to the application layer. Every reader already filters deleted_at
-- explicitly (iOS direct reads use .is('deleted_at', nil); tombstones flow via
-- get_photo_annotations_since). Side benefit: realtime UPDATE events for tombstoned
-- rows now reach same-company subscribers, so removals propagate live. There is
-- deliberately NO DELETE policy: client hard-delete stays impossible by design.
drop policy if exists "Users can read company annotations" on public.project_photo_annotations;

create policy "Users can read company annotations"
  on public.project_photo_annotations
  for select
  using (
    company_id = (select private.get_user_company_id())::text
  );
