-- Lazy-migration (server side): when the first author-scoped layer is written onto
-- a LEGACY row (annotation_url set, no layers), seed the existing overlay as a
-- layer owned by the row's ORIGINAL author. Otherwise re-deriving annotation_url
-- from the new layers would silently drop the legacy author's marks for everyone.
-- Writing another author's layer is only safe here (SECURITY DEFINER), never from
-- a client (the client RPC still enforces layerId == caller).
create or replace function public.upsert_markup_layer(
  p_annotation_id uuid,
  p_layer jsonb,
  p_change_event jsonb default null,
  p_before_url text default null,
  p_after_url text default null
)
returns public.project_photo_annotations
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_company_id uuid;
  v_user_id    uuid;
  v_layer_id   text;
  v_row        public.project_photo_annotations;
  v_base       jsonb;
  v_new_layers jsonb;
  v_new_log    jsonb;
  v_all_cleared boolean;
  v_overlay_url text;
begin
  v_company_id := private.get_user_company_id();
  v_user_id    := private.get_current_user_id();
  if v_company_id is null or v_user_id is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_layer is null then
    raise exception 'p_layer required' using errcode = '22023';
  end if;

  v_layer_id := p_layer ->> 'layerId';
  if v_layer_id is null or v_layer_id is distinct from v_user_id::text then
    raise exception 'May only upsert your own markup layer' using errcode = '42501';
  end if;

  select * into v_row
  from public.project_photo_annotations
  where id = p_annotation_id
    and company_id = v_company_id::text
  for update;

  if not found then
    raise exception 'Annotation not found' using errcode = 'P0002';
  end if;

  p_layer := p_layer || jsonb_build_object('authorId', v_user_id::text);

  -- Legacy seed: a row with a single overlay but no layers yet becomes a layer
  -- owned by its original author, so that author's marks survive as a peer layer.
  if (v_row.layers is null or jsonb_array_length(v_row.layers) = 0)
     and nullif(v_row.annotation_url, '') is not null then
    v_base := jsonb_build_array(jsonb_build_object(
      'layerId',        v_row.author_id,
      'authorId',       v_row.author_id,
      'authorName',     '',
      'overlayUrl',     v_row.annotation_url,
      'visibleDefault', true,
      'zIndex',         0,
      'createdAt',      v_row.created_at,
      'updatedAt',      coalesce(v_row.updated_at, v_row.created_at)
    ));
  else
    v_base := coalesce(v_row.layers, '[]'::jsonb);
  end if;

  -- Merge by layerId: drop the caller's prior layer (or the legacy seed if the
  -- caller IS the original author), append the new one.
  v_new_layers := coalesce(
    (select jsonb_agg(elem)
       from jsonb_array_elements(v_base) as elem
      where (elem ->> 'layerId') is distinct from v_layer_id),
    '[]'::jsonb
  ) || jsonb_build_array(p_layer);

  if p_change_event is null then
    v_new_log := v_row.change_log;
  else
    v_new_log := coalesce(v_row.change_log, '[]'::jsonb)
      || jsonb_build_array(p_change_event || jsonb_build_object('authorId', v_user_id::text));
  end if;

  v_all_cleared := not exists (
    select 1 from jsonb_array_elements(v_new_layers) as e
    where (e ->> 'clearedAt') is null
  );

  select e ->> 'overlayUrl' into v_overlay_url
  from jsonb_array_elements(v_new_layers) as e
  where (e ->> 'clearedAt') is null
    and nullif(e ->> 'overlayUrl', '') is not null
  order by (e ->> 'updatedAt') desc nulls last
  limit 1;

  update public.project_photo_annotations
  set layers = v_new_layers,
      change_log = v_new_log,
      before_snapshot_url = coalesce(p_before_url, before_snapshot_url),
      after_snapshot_url  = coalesce(p_after_url, after_snapshot_url),
      annotation_url = v_overlay_url,
      deleted_at = case
        when v_all_cleared and v_row.dimensions is null then now()
        else null
      end,
      updated_at = now()
  where id = p_annotation_id
  returning * into v_row;

  return v_row;
end;
$function$;
