-- Durable soft-delete write path for photo annotations (bugs 452bab04/0415504f).
-- Additive SECURITY DEFINER RPC; identity via the firebase_uid/auth_id bridge,
-- never auth.uid(). Companion to upsert_markup_layer. iOS calls this first and
-- falls back to the direct UPDATE when absent, so app + migration ship in any order.
create or replace function public.soft_delete_photo_annotation(p_annotation_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_company_id uuid;
  v_user_id uuid;
  v_id uuid;
begin
  v_company_id := private.get_user_company_id();
  v_user_id    := private.get_current_user_id();
  if v_company_id is null or v_user_id is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  update public.project_photo_annotations
     set deleted_at = coalesce(deleted_at, now()),
         updated_at = now()
   where id = p_annotation_id
     and company_id = v_company_id::text
   returning id into v_id;

  if v_id is null then
    raise exception 'Annotation not found' using errcode = 'P0002';
  end if;

  return v_id;
end;
$$;

grant execute on function public.soft_delete_photo_annotation(uuid) to anon, authenticated, service_role;
