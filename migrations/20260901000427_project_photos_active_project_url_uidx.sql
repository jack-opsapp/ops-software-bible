-- Cluster J / bug 16d487c4. Idempotency arbiter for the project-photo portal
-- mirror: one active row per (project_id, url). Site-visit rows keep their
-- narrower dedupe indexes; this one covers every active row.
do $$
begin
  if exists (
    select 1 from public.project_photos
    where deleted_at is null
    group by project_id, url having count(*) > 1
  ) then
    raise exception 'active (project_id,url) duplicates exist — dedupe before creating project_photos_active_project_url_uidx';
  end if;
end $$;

create unique index if not exists project_photos_active_project_url_uidx
  on public.project_photos (project_id, url)
  where deleted_at is null;
