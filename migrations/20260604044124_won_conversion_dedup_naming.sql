-- Won → Project Conversion: Dedup + Auto Project Naming (inert objects)

-- 1. projects.title_is_auto + collision index
alter table public.projects
  add column if not exists title_is_auto boolean not null default false;
comment on column public.projects.title_is_auto is
  'When true, title is auto-managed by the projects_autoname trigger (pointer to address). '
  'When false (default), title is hand-set and never auto-modified.';
create index if not exists projects_company_title_active
  on public.projects (company_id, title) where deleted_at is null;

-- 2. SQL normalizers
create or replace function private.normalize_address(p text)
returns text language sql immutable as $$
  with s1 as (
    select regexp_replace(lower(coalesce(p,'')),
             '[,\s]+(suite|ste|unit|apt|apartment|#)\s*\.?\s*\w+.*$', '', 'i') as s
  ),
  s2 as (
    select btrim(regexp_replace(regexp_replace(s, '[.,]', ' ', 'g'), '\s+', ' ', 'g')) as s from s1
  ),
  toks as (
    select w, ord from s2, regexp_split_to_table(s2.s, '\s+') with ordinality as t(w, ord) where w <> ''
  ),
  mapped as (
    select string_agg(
      case w
        when 'w' then 'west' when 'e' then 'east' when 'n' then 'north' when 's' then 'south'
        when 'nw' then 'northwest' when 'ne' then 'northeast' when 'sw' then 'southwest' when 'se' then 'southeast'
        when 'ave' then 'avenue' when 'av' then 'avenue'
        when 'st' then 'street' when 'str' then 'street'
        when 'rd' then 'road' when 'blvd' then 'boulevard' when 'boul' then 'boulevard'
        when 'dr' then 'drive' when 'cres' then 'crescent' when 'cr' then 'crescent'
        when 'hwy' then 'highway' when 'pl' then 'place' when 'ct' then 'court'
        when 'ln' then 'lane' when 'ter' then 'terrace' when 'pkwy' then 'parkway' when 'sq' then 'square'
        else w end, ' ' order by ord)
    from toks
  )
  select coalesce((select string_agg from mapped), '');
$$;

create or replace function private.normalize_title(p text)
returns text language sql immutable as $$
  with s1 as (select regexp_replace(coalesce(p,''), '^(re:\s*|fwd?:\s*|fw:\s*)*', '', 'i') as s),
  s2 as (select regexp_replace(s, '\y(new\s+)?(project|job)\s*[-:]\s*', '', 'gi') as s from s1),
  s3 as (select btrim(regexp_replace(lower(s), '\s+', ' ', 'g')) as s from s2)
  select case
    when s = '' then ''
    when s ~ '^(new project|proyecto nuevo)$' then ''
    when s ~ '''s project$' then ''
    else s end
  from s3;
$$;

-- 3. derive_project_name
create or replace function private.derive_project_name(p_address text, p_client_name text)
returns text language sql immutable as $$
  select case
    when nullif(btrim(p_address), '') is not null
      then coalesce(nullif(btrim(split_part(p_address, ',', 1)), ''), btrim(p_address))
    when nullif(btrim(p_client_name), '') is not null
      then btrim(p_client_name) || '''s Project'
    else 'New project'
  end;
$$;

-- 4. Enforce-always naming trigger
create or replace function private.projects_autoname()
returns trigger language plpgsql as $$
declare v_client_name text; v_base text; v_name text; n int := 2;
begin
  if new.title_is_auto is not true then return new; end if;
  if new.client_id is not null then
    select name into v_client_name from public.clients where id = new.client_id;
  end if;
  v_base := private.derive_project_name(new.address, v_client_name);
  v_name := v_base;
  while exists (
    select 1 from public.projects
     where company_id = new.company_id and deleted_at is null and id <> new.id and title = v_name
  ) loop
    v_name := v_base || ' #' || n; n := n + 1;
  end loop;
  new.title := v_name;
  return new;
end;
$$;
drop trigger if exists projects_autoname_biud on public.projects;
create trigger projects_autoname_biud
  before insert or update on public.projects
  for each row execute function private.projects_autoname();

-- 5. get_conversion_preflight (read-only)
create or replace function public.get_conversion_preflight(
  p_opportunity_id uuid, p_company_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public, private as $$
declare
  v_company uuid; v_opp public.opportunities%rowtype; v_client_name text;
  v_existing jsonb; v_candidates jsonb; v_others jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    v_company := private.get_user_company_id();
    if v_company is null then raise exception 'access_denied' using errcode='42501'; end if;
    if not private.current_user_has_permission('pipeline.manage','all') then
      raise exception 'access_denied' using errcode='42501'; end if;
  else
    v_company := p_company_id;
  end if;

  select * into v_opp from public.opportunities
   where id = p_opportunity_id and company_id = v_company and deleted_at is null;
  if not found then raise exception 'opportunity_not_found' using errcode='P0002'; end if;

  if v_opp.client_id is not null then
    select name into v_client_name from public.clients where id = v_opp.client_id;
  end if;

  select case when v_opp.project_ref is not null then
      (select jsonb_build_object('id', p.id, 'title', p.title)
         from public.projects p where p.id = v_opp.project_ref)
    else null end into v_existing;

  select coalesce(jsonb_agg(jsonb_build_object(
           'project_id', p.id, 'title', p.title, 'address', p.address,
           'confidence', case when p.client_id is not distinct from v_opp.client_id and v_opp.client_id is not null
                              then 'high' else 'medium' end,
           'signals', case when p.client_id is not distinct from v_opp.client_id and v_opp.client_id is not null
                           then jsonb_build_array('same_client','same_address')
                           else jsonb_build_array('same_address') end)), '[]'::jsonb)
    into v_candidates
    from public.projects p
   where p.company_id = v_company and p.deleted_at is null
     and (v_opp.project_ref is null or p.id <> v_opp.project_ref)
     and nullif(btrim(coalesce(v_opp.address,'')),'') is not null
     and private.normalize_address(p.address) = private.normalize_address(v_opp.address)
     and private.normalize_address(p.address) <> '';

  select coalesce(jsonb_agg(jsonb_build_object(
           'project_id', p.id, 'title', p.title, 'address', p.address, 'status', p.status)), '[]'::jsonb)
    into v_others
    from public.projects p
   where p.company_id = v_company and p.deleted_at is null
     and v_opp.client_id is not null and p.client_id = v_opp.client_id
     and (v_opp.project_ref is null or p.id <> v_opp.project_ref)
     and not (
       nullif(btrim(coalesce(v_opp.address,'')),'') is not null
       and private.normalize_address(p.address) = private.normalize_address(v_opp.address)
       and private.normalize_address(p.address) <> ''
     );

  return jsonb_build_object(
    'existing_linked_project', v_existing,
    'duplicate_candidates', v_candidates,
    'other_client_projects', v_others,
    'suggested_name', private.derive_project_name(v_opp.address, v_client_name)
  );
end;
$$;
grant execute on function public.get_conversion_preflight(uuid, uuid) to authenticated, service_role;

-- 6. Unified convert_opportunity_to_project
create or replace function public.convert_opportunity_to_project(
  p_company_id uuid, p_opportunity_id uuid, p_actual_value numeric default null,
  p_expected_stage text default null, p_decided_by uuid default null, p_notes text default null,
  p_title_override text default null, p_link_to_project_id uuid default null,
  p_source_path text default null, p_win_opportunity boolean default true,
  p_project_status text default null, p_evidence jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public, private as $$
declare
  v_opp public.opportunities%rowtype; v_project_id uuid; v_status text; v_value numeric;
  v_platform jsonb; v_disposition_id uuid; v_relinked bigint := 0; v_tasks bigint := 0;
  v_photos bigint := 0; v_won boolean := false; v_linked_existing boolean := (p_link_to_project_id is not null);
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    if p_company_id is distinct from private.get_user_company_id() then
      raise exception 'access_denied' using errcode='42501'; end if;
    if not private.current_user_has_permission('pipeline.manage','all') then
      raise exception 'access_denied' using errcode='42501'; end if;
  end if;
  if p_company_id is null or p_opportunity_id is null then
    raise exception 'company and opportunity ids are required' using errcode='22023';
  end if;

  select * into v_opp from public.opportunities
   where id = p_opportunity_id and company_id = p_company_id for update;
  if not found then raise exception 'opportunity_not_found' using errcode='P0002'; end if;
  if v_opp.deleted_at is not null then raise exception 'opportunity is soft-deleted' using errcode='22023'; end if;

  if v_opp.project_ref is not null then
    return jsonb_build_object('converted', false, 'already_converted', true,
      'guard_reason','already_converted', 'project_id', v_opp.project_ref, 'opportunity_id', p_opportunity_id);
  end if;

  if p_expected_stage is not null and v_opp.stage is distinct from p_expected_stage then
    return jsonb_build_object('converted', false, 'already_converted', false,
      'guard_reason','snapshot_mismatch', 'opportunity_id', p_opportunity_id);
  end if;

  v_status := coalesce(p_project_status, case when p_win_opportunity then 'accepted' else 'rfq' end);
  v_value  := coalesce(p_actual_value, v_opp.actual_value, v_opp.estimated_value);
  v_platform := case when v_opp.source is not null or v_opp.source_email_id is not null
                     then jsonb_build_object('source', v_opp.source, 'source_email_id', v_opp.source_email_id)
                     else null end;

  if v_linked_existing then
    select id into v_project_id from public.projects
     where id = p_link_to_project_id and company_id = p_company_id and deleted_at is null for update;
    if not found then raise exception 'link target project not found' using errcode='P0002'; end if;
    update public.projects
       set opportunity_ref = p_opportunity_id, opportunity_id = p_opportunity_id::text, updated_at = now()
     where id = v_project_id;
  else
    v_project_id := gen_random_uuid();
    insert into public.projects (
      id, company_id, client_id, opportunity_id, opportunity_ref,
      title, title_is_auto, address, latitude, longitude,
      status, source, estimated_value, platform_metadata, notes, created_by, created_at, updated_at
    ) values (
      v_project_id, p_company_id, v_opp.client_id, p_opportunity_id::text, p_opportunity_id,
      coalesce(p_title_override, 'New project'), (p_title_override is null),
      v_opp.address, v_opp.latitude, v_opp.longitude,
      v_status, v_opp.source, v_value, v_platform, p_notes, p_decided_by, now(), now()
    );
  end if;

  update public.opportunities
     set project_ref = v_project_id, project_id = v_project_id, updated_at = now()
   where id = p_opportunity_id and company_id = p_company_id and project_ref is null;
  if not found then
    raise exception 'opportunity link update matched zero rows (concurrent conversion?)' using errcode='P0002';
  end if;

  update public.estimates
     set project_ref = v_project_id, project_id = v_project_id::text, updated_at = now()
   where opportunity_id = p_opportunity_id and company_id = p_company_id and deleted_at is null;
  get diagnostics v_relinked = row_count;

  insert into public.project_tasks (
    id, company_id, project_id, task_type_id, custom_title,
    source_line_item_id, source_estimate_id, status, display_order, duration, task_color, created_at, updated_at)
  select gen_random_uuid(), p_company_id, v_project_id, li.task_type_ref, li.name,
         li.id::text, li.estimate_id::text, 'active', coalesce(li.sort_order,0),
         coalesce(tt.default_duration,1), coalesce(tt.color,'#417394'), now(), now()
    from public.line_items li
    left join public.task_types tt on tt.id = li.task_type_ref
   where li.estimate_id in (select id from public.estimates
                              where opportunity_id = p_opportunity_id and deleted_at is null)
     and li.type = 'LABOR'
     and not exists (select 1 from public.project_tasks pt
                      where pt.project_id = v_project_id and pt.source_line_item_id = li.id::text);
  get diagnostics v_tasks = row_count;

  insert into public.project_photos (
    id, project_id, company_id, url, source, site_visit_id, uploaded_by, taken_at, created_at)
  select gen_random_uuid(), v_project_id::text, p_company_id::text, photo_url, 'site_visit',
         sv.id, sv.created_by, null, now()
    from public.site_visits sv
    cross join lateral unnest(sv.photos) as photo_url
   where sv.opportunity_id = p_opportunity_id and sv.deleted_at is null
     and photo_url is not null and photo_url <> ''
     and not exists (select 1 from public.project_photos pp
                      where pp.project_id = v_project_id::text and pp.site_visit_id = sv.id and pp.url = photo_url);
  get diagnostics v_photos = row_count;

  if p_win_opportunity then
    if v_opp.stage is distinct from 'won' then
      update public.opportunities
         set stage='won', stage_entered_at=now(), stage_manually_set=true,
             actual_value=coalesce(p_actual_value, actual_value), actual_close_date=now()::date, updated_at=now()
       where id = p_opportunity_id;
      insert into public.stage_transitions (
        company_id, opportunity_id, from_stage, to_stage, transitioned_at, transitioned_by, duration_in_stage)
      values (p_company_id, p_opportunity_id, v_opp.stage, 'won', now(), p_decided_by,
              now() - coalesce(v_opp.stage_entered_at, now()));
      v_won := true;
    else
      update public.opportunities set actual_value=coalesce(p_actual_value, actual_value), updated_at=now()
       where id = p_opportunity_id;
    end if;
  end if;

  update public.opportunity_dispositions set superseded_at = now()
   where opportunity_id = p_opportunity_id and company_id = p_company_id and superseded_at is null;
  insert into public.opportunity_dispositions (
    company_id, opportunity_id, disposition, reason_code, decided_via, decided_by, evidence, converted_project_ref)
  values (p_company_id, p_opportunity_id, 'converted_to_project', null, 'project_conversion', p_decided_by,
          coalesce(p_evidence,'{}'::jsonb) || jsonb_build_object(
            'source_path', p_source_path, 'actual_value', v_value,
            'relinked_estimates', v_relinked, 'linked_existing', v_linked_existing, 'won', v_won),
          v_project_id)
  returning id into v_disposition_id;

  return jsonb_build_object(
    'converted', true, 'already_converted', false, 'project_id', v_project_id,
    'opportunity_id', p_opportunity_id, 'disposition_id', v_disposition_id,
    'relinked_estimates', v_relinked, 'materialized_tasks', v_tasks, 'attached_photos', v_photos,
    'linked_existing', v_linked_existing, 'won', v_won);
end;
$$;
grant execute on function public.convert_opportunity_to_project(
  uuid, uuid, numeric, text, uuid, text, text, uuid, text, boolean, text, jsonb) to authenticated, service_role;
