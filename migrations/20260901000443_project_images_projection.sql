-- Cluster J / bug 16d487c4. The legacy CSV becomes a server projection.
-- SECURITY DEFINER is load-bearing: the projection write must not depend on
-- the uploading operator holding projects.edit (that dependency IS the bug).

create or replace function private.project_images_apply_mirror()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $$
declare
  v_project_id uuid;
begin
  v_project_id := private.project_table_project_id_from_text(new.project_id);
  if v_project_id is null then
    return null;  -- malformed legacy id: nothing to project onto
  end if;

  if tg_op = 'INSERT' and new.deleted_at is null then
    update public.projects
       set project_images = project_images || new.url
     where id = v_project_id
       and not (coalesce(project_images, '{}') @> array[new.url]);
  elsif tg_op = 'UPDATE' then
    if new.deleted_at is not null and old.deleted_at is null then
      update public.projects
         set project_images = array_remove(coalesce(project_images, '{}'), new.url)
       where id = v_project_id
         and coalesce(project_images, '{}') @> array[new.url];
    elsif new.deleted_at is null and old.deleted_at is not null then
      update public.projects
         set project_images = project_images || new.url
       where id = v_project_id
         and not (coalesce(project_images, '{}') @> array[new.url]);
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists zz1_project_photos_mirror_csv on public.project_photos;
create trigger zz1_project_photos_mirror_csv
  after insert or update of deleted_at on public.project_photos
  for each row execute function private.project_images_apply_mirror();

-- Union guard: no writer (including shipped iOS builds that still PATCH the
-- whole array) can drop an active mirrored URL or resurrect a tombstoned one.
create or replace function private.project_images_union_guard()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $$
declare
  active_urls  text[];
  deleted_urls text[];
  merged       text[] := '{}';
  u            text;
begin
  select coalesce(array_agg(url order by created_at), '{}') into active_urls
    from public.project_photos
   where project_id = new.id::text and deleted_at is null;
  select coalesce(array_agg(distinct url), '{}') into deleted_urls
    from public.project_photos
   where project_id = new.id::text
     and deleted_at is not null
     and url <> all (active_urls);

  foreach u in array coalesce(new.project_images, '{}') loop
    if not (u = any (deleted_urls)) and not (u = any (merged)) then
      merged := merged || u;
    end if;
  end loop;
  foreach u in array active_urls loop
    if not (u = any (merged)) then
      merged := merged || u;
    end if;
  end loop;

  new.project_images := merged;
  return new;
end;
$$;

drop trigger if exists zz2_projects_project_images_union on public.projects;
create trigger zz2_projects_project_images_union
  before update of project_images on public.projects
  for each row execute function private.project_images_union_guard();
