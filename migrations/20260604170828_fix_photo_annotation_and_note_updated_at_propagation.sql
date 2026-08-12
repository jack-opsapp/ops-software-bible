-- Root cause: project_photo_annotations.updated_at and project_notes.updated_at
-- had no DEFAULT and no trigger, so freshly inserted rows landed with
-- updated_at = NULL. Delta sync pulls filter `updated_at >= p_since`, and
-- NULL >= p_since is NULL (excluded) — so new markup/comments never reached
-- other devices. Bring both tables in line with the projects/expenses
-- convention (default now() + BEFORE UPDATE trigger), backfill the NULL rows,
-- and harden the photo-annotation pull RPC with COALESCE for resilience.

-- ============ project_photo_annotations (markup) ============
alter table public.project_photo_annotations
  alter column updated_at set default now();

update public.project_photo_annotations
  set updated_at = created_at
  where updated_at is null;

drop trigger if exists update_project_photo_annotations_timestamp
  on public.project_photo_annotations;
create trigger update_project_photo_annotations_timestamp
  before update on public.project_photo_annotations
  for each row execute function public.update_timestamp();

create or replace function public.get_photo_annotations_since(
  p_since timestamp with time zone default null::timestamp with time zone
)
returns setof project_photo_annotations
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_company_id uuid;
begin
  v_company_id := private.get_user_company_id();
  if v_company_id is null then
    return;
  end if;

  return query
  select *
  from public.project_photo_annotations
  where company_id = v_company_id::text
    and (p_since is null or coalesce(updated_at, created_at) >= p_since)
  order by created_at desc;
end;
$function$;

-- ============ project_notes (photo comments — identical bug) ============
alter table public.project_notes
  alter column updated_at set default now();

update public.project_notes
  set updated_at = created_at
  where updated_at is null;

drop trigger if exists update_project_notes_timestamp
  on public.project_notes;
create trigger update_project_notes_timestamp
  before update on public.project_notes
  for each row execute function public.update_timestamp();
