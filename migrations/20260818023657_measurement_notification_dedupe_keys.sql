-- Measurement notification dedupe keys (follow-up to
-- 20260818023254_ios_notification_surface_rpcs, bug e302355c).
--
-- notify_measurement_captured rows carried no dedupe_key, so the platform's
-- unread dedupe index — UNIQUE (user_id, company_id, type,
-- COALESCE(dedupe_key, title)) WHERE is_read = false — collapsed every capture
-- into the first unread one: all captures share the title
-- '// MEASUREMENT SAVED', and a crew measuring several openings back-to-back
-- lost every confirmation after the first (verified in RPC test: a
-- wall-section capture returned 'noop' while an opening capture sat unread).
-- Distinct dimensions are distinct information; key the row on the rendered
-- body so only a byte-identical duplicate capture dedupes while unread.
-- Same reasoning for notify_measurement_sync_failed across projects: key per
-- project so one project's unread failure cannot swallow another's.

create or replace function public.notify_measurement_captured(
  p_project_id uuid,
  p_kind text,
  p_width_inches integer default null,
  p_height_inches integer default null,
  p_opening_type text default null,
  p_sill_inches integer default null,
  p_wall_width_feet integer default null,
  p_wall_width_inches integer default null,
  p_wall_height_feet integer default null
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project_title text;
  v_body text;
  v_wall_width text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(p.title), ''), 'Untitled project')
  into v_project_title
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  if p_kind = 'opening' then
    if p_width_inches is null or p_width_inches not between 0 and 100000
       or p_height_inches is null or p_height_inches not between 0 and 100000
       or p_sill_inches is null or p_sill_inches not between 0 and 100000
       or p_opening_type is null
       or p_opening_type not in ('window', 'door') then
      raise exception 'invalid opening measurement'
        using errcode = '22023';
    end if;
    v_body := upper(v_project_title)
      || ' · ' || p_width_inches || '″×' || p_height_inches || '″ '
      || upper(p_opening_type)
      || ' · SILL ' || p_sill_inches || '″';
  elsif p_kind = 'wall_section' then
    if p_wall_width_feet is null or p_wall_width_feet not between 0 and 100000
       or p_wall_width_inches is null or p_wall_width_inches not between 0 and 100000
       or p_wall_height_feet is null or p_wall_height_feet not between 0 and 100000 then
      raise exception 'invalid wall section measurement'
        using errcode = '22023';
    end if;
    if p_wall_width_inches = 0 then
      v_wall_width := p_wall_width_feet || '′';
    else
      v_wall_width := p_wall_width_feet || '′' || p_wall_width_inches || '″';
    end if;
    v_body := upper(v_project_title)
      || ' · WALL SECTION · ' || v_wall_width
      || ' × ' || p_wall_height_feet || '′';
  else
    raise exception 'unknown measurement kind'
      using errcode = '22023';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'measurement_captured',
    '// MEASUREMENT SAVED', v_body,
    false, false, p_project_id::text, 'projectDetails',
    null, 'VIEW',
    'measurement-captured:' || md5(v_body)
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

create or replace function public.notify_measurement_sync_failed(
  p_project_id uuid
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project_title text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(p.title), ''), 'Untitled project')
  into v_project_title
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'measurement_sync_failed',
    '// ERROR — SYNC FAILED',
    upper(v_project_title) || ' · MEASUREMENT NOT UPLOADED · RETRY',
    false, false, p_project_id::text, 'projectDetails',
    null, 'RETRY',
    'measurement-failed:' || p_project_id::text
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;
