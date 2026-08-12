-- Bug 0f86b9b0 / c6e90385 follow-up: projects.vinyl_ordered_by referenced
-- auth.users(id), but under the Firebase JWT bridge the app's identities live
-- in public.users (a public.users.id is never present in auth.users). The
-- column had 0 populated rows, so "mark vinyl ordered" attribution could never
-- persist. Retarget the FK to public.users(id), mirroring
-- catalog_orders.created_by_id (FK users(id) ON DELETE SET NULL). Safe: 0 rows
-- populated so no existing data can violate the new constraint; transparent to
-- installed iOS builds (column stays uuid).
alter table public.projects drop constraint if exists projects_vinyl_ordered_by_fkey;
alter table public.projects
  add constraint projects_vinyl_ordered_by_fkey
  foreign key (vinyl_ordered_by) references public.users(id) on delete set null;
