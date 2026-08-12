-- Collaborative photo markup: author-scoped layers, per-author change log,
-- and (forward-ready) before/after snapshots. ADDITIVE ONLY.
-- Requested by Jackson 2026-06-23. Spec: docs/superpowers/specs/2026-06-23-photo-markup-collab-spec.md
-- get_photo_annotations_since is RETURNS SETOF ... select *, so these columns
-- auto-surface on the existing sync pull.

alter table public.project_photo_annotations
  add column if not exists layers jsonb,
  add column if not exists change_log jsonb,
  add column if not exists before_snapshot_url text,
  add column if not exists after_snapshot_url text;

comment on column public.project_photo_annotations.layers is
  'Author-scoped collaborative markup layers. Array of {layerId,authorId,authorName,overlayUrl,strokeRef,visibleDefault,zIndex,createdAt,updatedAt,clearedAt}. layerId == authorId == users.id. Merged server-side by upsert_markup_layer (NEVER a wholesale update().eq(id)).';
comment on column public.project_photo_annotations.change_log is
  'Append-only per-author markup change events. Array of {eventId,authorId,authorName,action,strokeDelta,beforeSnapshotUrl,afterSnapshotUrl,at}.';
comment on column public.project_photo_annotations.before_snapshot_url is
  'Most-recent markup event baked BEFORE composite (frozen pixels). Activity-feed before/after card. Forward-ready: null until snapshots ship.';
comment on column public.project_photo_annotations.after_snapshot_url is
  'Most-recent markup event baked AFTER composite (frozen pixels). Activity-feed before/after card. Forward-ready: null until snapshots ship.';

-- Atomic server-side layer merge. Identity via the established firebase_uid/auth_id
-- bridge (private.get_current_user_id / private.get_user_company_id) — NEVER auth.uid().
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
  -- Security invariant: a caller may write ONLY their own layer. layerId == user id,
  -- so this blocks overwriting a peer's layer by spoofing their layerId.
  if v_layer_id is null or v_layer_id is distinct from v_user_id::text then
    raise exception 'May only upsert your own markup layer' using errcode = '42501';
  end if;

  -- Lock the anchor row, company-scoped (mirrors the table SELECT/UPDATE RLS).
  select * into v_row
  from public.project_photo_annotations
  where id = p_annotation_id
    and company_id = v_company_id::text
  for update;

  if not found then
    raise exception 'Annotation not found' using errcode = 'P0002';
  end if;

  -- Defence in depth: stamp the server-trusted author id onto the layer.
  p_layer := p_layer || jsonb_build_object('authorId', v_user_id::text);

  -- Merge by layerId: drop the caller's prior layer, append the new one.
  v_new_layers := coalesce(
    (select jsonb_agg(elem)
       from jsonb_array_elements(coalesce(v_row.layers, '[]'::jsonb)) as elem
      where (elem ->> 'layerId') is distinct from v_layer_id),
    '[]'::jsonb
  ) || jsonb_build_array(p_layer);

  -- Append change event (server-stamped author) when supplied.
  if p_change_event is null then
    v_new_log := v_row.change_log;
  else
    v_new_log := coalesce(v_row.change_log, '[]'::jsonb)
      || jsonb_build_array(p_change_event || jsonb_build_object('authorId', v_user_id::text));
  end if;

  -- A layer is "active" when clearedAt is null/absent.
  v_all_cleared := not exists (
    select 1 from jsonb_array_elements(v_new_layers) as e
    where (e ->> 'clearedAt') is null
  );

  -- Legacy scalar back-compat: point annotation_url at the newest ACTIVE overlay
  -- (or null when no active markup). Keeps pre-update builds + AnnotationFeedPolicy
  -- (hasMarkup) honest.
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
      -- Whole-row soft-delete ONLY when every layer is cleared AND there is no
      -- dimensioned capture to preserve. Any active/new layer re-surfaces the row.
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

grant execute on function public.upsert_markup_layer(uuid, jsonb, jsonb, text, text)
  to anon, authenticated, service_role;
