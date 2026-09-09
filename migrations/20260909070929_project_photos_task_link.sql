-- A photo may document one project task (bug a290934f).
--
-- Additive and nullable so every installed iOS build and the web app keep
-- working untouched: their inserts and reads never mention the column.

alter table public.project_photos
  add column if not exists task_id uuid null
    references public.project_tasks(id) on delete set null;

comment on column public.project_photos.task_id is
  'Optional link to the project task this photo documents (bug a290934f). Nullable. The task must belong to the same project as the photo; enforced by project_photos_write_guard().';

-- Reading a task''s photos is the hot path: the task strip on Task Details and
-- the gallery''s task badges both filter live rows by (project, task).
create index if not exists project_photos_project_task_idx
  on public.project_photos (project_id, task_id)
  where deleted_at is null and task_id is not null;

-- The table grants SELECT and column-scoped INSERT/UPDATE only. Capture writes
-- the link on insert; the viewer reassigns it on update.
grant insert (task_id) on public.project_photos to anon, authenticated;
grant update (task_id) on public.project_photos to anon, authenticated;

-- Answers a question about the DATA, not about the operator''s read scope: a
-- task-scoped photo must never fail to deliver because the uploader cannot see
-- the task row under RLS. Authorization is the guard''s ownership/permission
-- half, which runs separately.
create or replace function private.project_photo_task_matches_project(
  p_task_id uuid,
  p_project_id text
)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $body$
  select exists (
    select 1
    from public.project_tasks t
    where t.id = p_task_id
      and t.deleted_at is null
      and t.project_id = private.project_table_project_id_from_text(p_project_id)
  );
$body$;

-- The write guard gains a task-link rule mirroring the soft-delete rule, plus a
-- project-membership rule that also runs on INSERT (capture stamps the link at
-- insert time, so an UPDATE-only guard would never see it).
create or replace function public.project_photos_write_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $body$
DECLARE
  v_uid uuid;
  v_task_changed boolean;
BEGIN
  IF current_user NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
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

    v_task_changed := NEW.task_id IS DISTINCT FROM OLD.task_id;

    IF v_task_changed THEN
      v_uid := private.resolve_uid();
      IF v_uid IS NULL THEN
        RAISE EXCEPTION 'project_photos: task link requires a resolvable user'
          USING ERRCODE = '42501';
      END IF;
      IF lower(OLD.uploaded_by) <> lower(v_uid::text)
         AND NOT private.current_user_has_permission('projects.edit', 'all') THEN
        RAISE EXCEPTION 'project_photos: task link allowed on own photos only'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  ELSE
    v_task_changed := NEW.task_id IS NOT NULL;
  END IF;

  IF v_task_changed AND NEW.task_id IS NOT NULL
     AND NOT private.project_photo_task_matches_project(NEW.task_id, NEW.project_id) THEN
    RAISE EXCEPTION 'project_photos: task must belong to the photo project'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$body$;

drop trigger if exists trg_project_photos_00_write_guard on public.project_photos;
create trigger trg_project_photos_00_write_guard
  before insert or update on public.project_photos
  for each row execute function public.project_photos_write_guard();
