-- Bug f5f57917: remove attachments without deleting the project note.
-- UNAPPLIED. Independent of the pending expense/project-reopen migrations.
-- Reviewed successor to the untouched 2026-09-04 iOS staged artifact.
-- Baseline captured read-only from ops-app on 2026-09-14 at 22:38 UTC:
-- 4-arg MD5 9d16ec64ff2d15da9e00fe1fbeb1adc4; owner postgres;
-- EXECUTE exactly postgres, anon, authenticated. Public schema defaults ALSO
-- grant service_role, so CREATE is followed by a complete ACL reset.
-- Legacy 4-argument/SQL-NULL requests preserve semantics and response keys.
-- Explicit arrays are removal-only, preserving exact order and multiplicity.
-- No gallery/storage writes; no notification/provider work is added here.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $guard$
declare
  v_oid oid := to_regprocedure('public.update_project_note_mentions(uuid,text,text[],uuid)');
  v_acl text[];
begin
  if v_oid is null or
     (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='update_project_note_mentions') <> 1 or
     md5(pg_get_functiondef(v_oid)) <> '9d16ec64ff2d15da9e00fe1fbeb1adc4' or
     (select pg_get_userbyid(proowner) from pg_proc where oid=v_oid) <> 'postgres' then
    raise exception 'project note attachment migration function baseline drift' using errcode='55000';
  end if;
  select array_agg(grantee::regrole::text || ':' || privilege_type || ':' || is_grantable::text order by grantee::regrole::text)
    into v_acl from aclexplode((select proacl from pg_proc where oid=v_oid));
  if v_acl is distinct from array['anon:EXECUTE:false','authenticated:EXECUTE:false','postgres:EXECUTE:false'] then
    raise exception 'project note attachment migration ACL baseline drift' using errcode='55000';
  end if;
  if exists(select 1 from pg_depend where refclassid='pg_proc'::regclass and refobjid=v_oid)
     or exists(select 1 from pg_proc where oid<>v_oid and prokind in ('f','p')
               and prosrc like '%update_project_note_mentions%') then
    raise exception 'project note attachment migration has dependent callers' using errcode='55000';
  end if;
  if exists (
    select 1 from (values
      ('project_note_mention_events','id','uuid',true),
      ('project_note_mention_events','note_id','uuid',true),
      ('project_note_mention_events','project_id','text',true),
      ('project_note_mention_events','company_id','uuid',true),
      ('project_note_mention_events','actor_user_id','uuid',true),
      ('project_note_mention_events','requested_content','text',true),
      ('project_note_mention_events','requested_mentioned_user_ids','_text',true),
      ('project_note_mention_events','prior_content_snapshot','text',true),
      ('project_note_mention_events','prior_mentioned_user_ids','_text',true),
      ('project_note_mention_events','content_snapshot','text',true),
      ('project_note_mention_events','mentioned_user_ids_snapshot','_text',true),
      ('project_note_mention_events','recipient_user_ids','_text',true),
      ('project_note_mention_events','actor_name_snapshot','text',true),
      ('project_note_mention_events','project_title_snapshot','text',true),
      ('project_note_mention_events','note_updated_at','timestamptz',true),
      ('project_note_mention_events','created_at','timestamptz',true),
      ('project_notes','id','uuid',true),
      ('project_notes','project_id','text',true),
      ('project_notes','company_id','text',true),
      ('project_notes','author_id','text',true),
      ('project_notes','content','text',true),
      ('project_notes','attachments','jsonb',true),
      ('project_notes','mentioned_user_ids','_text',true),
      ('project_notes','created_at','timestamptz',true),
      ('project_notes','updated_at','timestamptz',false),
      ('project_notes','deleted_at','timestamptz',false),
      ('project_notes','photo_url','text',false),
      ('project_notes','event_kind','text',false),
      ('project_notes','content_metadata','jsonb',false),
      ('projects','id','uuid',true),
      ('projects','company_id','uuid',true),
      ('projects','title','text',true),
      ('projects','status','text',true),
      ('projects','deleted_at','timestamptz',false),
      ('projects','status_version','int8',true),
      ('users','id','uuid',true),
      ('users','company_id','uuid',false),
      ('users','first_name','text',true),
      ('users','last_name','text',true),
      ('users','is_active','bool',false),
      ('users','auth_id','text',false),
      ('users','deleted_at','timestamptz',false),
      ('users','firebase_uid','text',false)
    ) expected(table_name,column_name,udt_name,not_null)
    left join pg_namespace n on n.nspname='public'
    left join pg_class c on c.relnamespace=n.oid and c.relname=expected.table_name
    left join pg_attribute a on a.attrelid=c.oid and a.attname=expected.column_name and not a.attisdropped
    left join pg_type t on t.oid=a.atttypid
    where t.typname is distinct from expected.udt_name or a.attnotnull is distinct from expected.not_null
  ) or exists(select 1 from pg_attribute where attrelid='public.project_note_mention_events'::regclass
              and attname in ('requested_attachments','attachments_snapshot') and not attisdropped) then
    raise exception 'project note attachment migration schema baseline drift' using errcode='55000';
  end if;
  if not exists(select 1 from pg_class where oid='public.project_note_mention_events'::regclass
                and relrowsecurity and not relforcerowsecurity and relowner='postgres'::regrole)
     or not exists(select 1 from pg_class where oid='public.project_notes'::regclass and relrowsecurity)
     or exists(select 1 from pg_class c cross join lateral aclexplode(c.relacl) acl
               where c.oid='public.project_note_mention_events'::regclass
                 and acl.grantee<>c.relowner
                 and not (acl.grantee='service_role'::regrole and acl.privilege_type='SELECT' and not acl.is_grantable))
     or not exists(select 1 from pg_class c cross join lateral aclexplode(c.relacl) acl
                   where c.oid='public.project_note_mention_events'::regclass
                     and acl.grantee='service_role'::regrole and acl.privilege_type='SELECT' and not acl.is_grantable)
     or not exists(select 1 from pg_policy where polrelid='public.project_note_mention_events'::regclass
                   and polname='project_note_mention_events_no_client_access' and not polpermissive
                   and polcmd='*' and polroles @> array['anon'::regrole::oid,'authenticated'::regrole::oid]
                   and pg_get_expr(polqual,polrelid)='false' and pg_get_expr(polwithcheck,polrelid)='false')
     or not exists(select 1 from pg_trigger where tgrelid='public.project_note_mention_events'::regclass
                   and tgname='project_note_mention_events_immutable' and tgenabled='O'
                   and tgtype=27 and tgnargs=0
                   and tgfoid='private.project_note_mention_events_are_immutable()'::regprocedure)
     or md5(pg_get_functiondef('private.project_note_mention_events_are_immutable()'::regprocedure))
        <> '663c280831375d0a14ab477f4da39797'
     or md5(pg_get_functiondef('private.get_current_user_id()'::regprocedure))
        <> '127ffd06387933500d95f96aba24b605'
     or md5(pg_get_functiondef('private.get_user_company_id()'::regprocedure))
        <> '3de642ffe4b81ee8827c1cc6507f85c4' then
    raise exception 'project note attachment migration authority baseline drift' using errcode='55000';
  end if;
end;
$guard$;

-- NULL on historical events means the request predates attachment provenance.
-- Do not backfill history from today's mutable note.
alter table public.project_note_mention_events
  add column requested_attachments jsonb,
  add column attachments_snapshot jsonb;

-- A single defaulted signature keeps PostgREST named calls unambiguous.
-- RESTRICT (the default) intentionally refuses any uncaptured dependency.
drop function public.update_project_note_mentions(uuid,text,text[],uuid);

CREATE OR REPLACE FUNCTION public.update_project_note_mentions(p_note_id uuid, p_content text, p_mentioned_user_ids text[], p_event_id uuid, p_attachments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp'
AS $function$
declare
  v_actor_id uuid := private.get_current_user_id();
  v_company_id uuid := private.get_user_company_id();
  v_existing public.project_notes%rowtype;
  v_replay public.project_note_mention_events%rowtype;
  v_actor_name text;
  v_project_title text;
  v_effective_mentioned_user_ids text[] := '{}'::text[];
  v_added_recipient_ids text[] := '{}'::text[];
  v_updated_at timestamptz;
  v_attachment jsonb;
  v_attachment_position bigint := 0;
  v_next_attachment_position bigint;
  -- Match the client's whitespace-and-newline emptiness test without
  -- rewriting opaque stored attachment strings.
  v_whitespace constant text := U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000';
begin
  if p_note_id is null or p_event_id is null or p_content is null then
    raise exception 'invalid project note mention edit'
      using errcode = '22023';
  end if;
  if p_mentioned_user_ids is null then
    raise exception 'explicit mention list is required'
      using errcode = '22023';
  end if;
  if array_position(p_mentioned_user_ids, null) is not null then
    raise exception 'requested mention user id is invalid'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from unnest(p_mentioned_user_ids) requested(user_id)
    where requested.user_id !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) then
    raise exception 'requested mention user id is invalid'
      using errcode = '22023';
  end if;
  -- Omitted/SQL NULL is the legacy text-and-mentions contract.
  if p_attachments is not null then
    if jsonb_typeof(p_attachments) <> 'array' then
      raise exception 'note attachments must be a json array' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(p_attachments) entry
               where jsonb_typeof(entry) <> 'string') then
      raise exception 'note attachments must be an array of strings' using errcode = '22023';
    end if;
  end if;

  select concat_ws(
    ' ',
    nullif(btrim(actor.first_name), ''),
    nullif(btrim(actor.last_name), '')
  )
    into v_actor_name
  from public.users actor
  where actor.id = v_actor_id
    and actor.company_id = v_company_id
    and actor.is_active
    and actor.deleted_at is null
  for share;

  if not found then
    raise exception 'project note mention edit actor is unavailable'
      using errcode = '42501';
  end if;
  if v_actor_id is null or v_company_id is null then
    raise exception 'project note mention edit actor is unavailable'
      using errcode = '42501';
  end if;
  v_actor_name := coalesce(nullif(btrim(v_actor_name), ''), 'A team member');

  -- Every edit of one note serializes here. A replay waits for the first call,
  -- then reads its immutable event instead of applying the stale mutation over
  -- any newer edit.
  select *
    into v_existing
  from public.project_notes
  where id = p_note_id
  for update;

  if not found then
    raise exception 'project note mention edit is unavailable'
      using errcode = '42501';
  end if;

  select event.*
    into v_replay
  from public.project_note_mention_events event
  where event.id = p_event_id;

  if found then
    if v_replay.note_id = p_note_id
       and v_replay.actor_user_id = v_actor_id
       and v_replay.company_id = v_company_id
       and v_replay.requested_content is not distinct from p_content
       and v_replay.requested_mentioned_user_ids is not distinct from p_mentioned_user_ids
       and v_replay.requested_attachments is not distinct from p_attachments then
      return jsonb_build_object(
        'event_id', v_replay.id,
        'note_id', v_replay.note_id,
        'project_id', v_replay.project_id,
        'content', v_replay.content_snapshot,
        'mentioned_user_ids', v_replay.mentioned_user_ids_snapshot,
        'recipient_user_ids', v_replay.recipient_user_ids,
        'added_count', cardinality(v_replay.recipient_user_ids),
        'updated_at', v_replay.note_updated_at,
        'replayed', true
      ) || case when p_attachments is null then '{}'::jsonb
                else jsonb_build_object('attachments', v_replay.attachments_snapshot) end;
    end if;
    raise exception 'mention edit event id was reused with a different request'
      using errcode = '22023';
  end if;

  if v_existing.author_id is distinct from v_actor_id::text
     or v_existing.company_id is distinct from v_company_id::text
     or v_existing.deleted_at is not null
     or v_existing.event_kind is not null then
    raise exception 'project note mention edit is unavailable'
      using errcode = '42501';
  end if;

  -- Validate only a NEW event against the locked current note. An exact
  -- replay above must never reapply its old attachment set over a newer edit.
  if p_attachments is not null then
    if jsonb_typeof(v_existing.attachments) <> 'array' then
      raise exception 'existing note attachments are unavailable' using errcode = '22023';
    end if;
    -- An ordered subsequence consumes each existing occurrence at most once:
    -- no insertion, reordering, duplicate amplification or string rewriting.
    -- Retaining legacy blanks/duplicates is compatible with the shipped editor.
    for v_attachment in select value from jsonb_array_elements(p_attachments) loop
      select min(entry.ordinality) into v_next_attachment_position
      from jsonb_array_elements(v_existing.attachments) with ordinality entry(value, ordinality)
      where entry.ordinality > v_attachment_position and entry.value = v_attachment;
      if v_next_attachment_position is null then
        raise exception 'note attachment edits may only remove existing attachments' using errcode = '22023';
      end if;
      v_attachment_position := v_next_attachment_position;
    end loop;

    -- photo_url is the comment's subject, never changed by this command.
    -- Blank survivors are not photos, even when they remain in the raw array.
    if btrim(p_content, v_whitespace) = ''
       and coalesce(btrim(v_existing.photo_url, v_whitespace), '') = ''
       and not exists (
         select 1 from jsonb_array_elements_text(p_attachments) entry(value)
         where btrim(entry.value, v_whitespace) <> ''
       ) then
      raise exception 'a note must keep either text or a photo' using errcode = '22023';
    end if;
  end if;

  select coalesce(
    array_agg(candidate.user_id order by candidate.ordinality),
    '{}'::text[]
  )
    into v_effective_mentioned_user_ids
  from (
    select normalized.user_id, min(normalized.ordinality) as ordinality
    from (
      select
        requested.user_id::uuid::text as user_id,
        requested.ordinality
      from unnest(p_mentioned_user_ids)
        with ordinality as requested(user_id, ordinality)
    ) normalized
    group by normalized.user_id
  ) candidate
  where candidate.user_id <> v_actor_id::text;

  if exists (
    select 1
    from unnest(v_effective_mentioned_user_ids) candidate(user_id)
    where not exists (
      select 1
      from public.users user_row
      where user_row.id = candidate.user_id::uuid
        and user_row.company_id = v_company_id
        and user_row.is_active
        and user_row.deleted_at is null
    )
  ) then
    raise exception 'requested mention user is not active in actor company'
      using errcode = '22023';
  end if;

  select project.title
    into v_project_title
  from public.projects project
  where project.id::text = v_existing.project_id
    and project.company_id = v_company_id
    and project.deleted_at is null
  for share;

  if not found then
    raise exception 'project note mention edit project is unavailable'
      using errcode = '42501';
  end if;
  v_project_title := coalesce(
    nullif(btrim(v_project_title), ''),
    'Untitled project'
  );

  select coalesce(
    array_agg(candidate.user_id order by candidate.ordinality),
    '{}'::text[]
  )
    into v_added_recipient_ids
  from unnest(v_effective_mentioned_user_ids)
    with ordinality as candidate(user_id, ordinality)
  where candidate.user_id in (
    select unnest(v_effective_mentioned_user_ids)
    except
    select prior.user_id::uuid::text
    from unnest(coalesce(v_existing.mentioned_user_ids, '{}'::text[]))
      as prior(user_id)
    where prior.user_id ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

  if p_attachments is null then
    -- Preserve the original UPDATE column list, including UPDATE OF trigger
    -- semantics, for every legacy four-argument / SQL-NULL request.
    update public.project_notes
    set content = p_content,
        mentioned_user_ids = v_effective_mentioned_user_ids,
        updated_at = clock_timestamp()
    where id = p_note_id
    returning updated_at into v_updated_at;
  else
    update public.project_notes
    set content = p_content,
        mentioned_user_ids = v_effective_mentioned_user_ids,
        attachments = p_attachments,
        updated_at = clock_timestamp()
    where id = p_note_id
    returning updated_at into v_updated_at;
  end if;

  insert into public.project_note_mention_events (
    id,
    note_id,
    project_id,
    company_id,
    actor_user_id,
    requested_content,
    requested_mentioned_user_ids,
    requested_attachments,
    attachments_snapshot,
    prior_content_snapshot,
    prior_mentioned_user_ids,
    content_snapshot,
    mentioned_user_ids_snapshot,
    recipient_user_ids,
    actor_name_snapshot,
    project_title_snapshot,
    note_updated_at
  ) values (
    p_event_id,
    p_note_id,
    v_existing.project_id,
    v_company_id,
    v_actor_id,
    p_content,
    p_mentioned_user_ids,
    p_attachments,
    coalesce(p_attachments, v_existing.attachments),
    v_existing.content,
    coalesce(v_existing.mentioned_user_ids, '{}'::text[]),
    p_content,
    v_effective_mentioned_user_ids,
    v_added_recipient_ids,
    v_actor_name,
    v_project_title,
    v_updated_at
  );

  return jsonb_build_object(
    'event_id', p_event_id,
    'note_id', p_note_id,
    'project_id', v_existing.project_id,
    'content', p_content,
    'mentioned_user_ids', v_effective_mentioned_user_ids,
    'recipient_user_ids', v_added_recipient_ids,
    'added_count', cardinality(v_added_recipient_ids),
    'updated_at', v_updated_at,
    'replayed', false
  ) || case when p_attachments is null then '{}'::jsonb
            else jsonb_build_object('attachments', coalesce(p_attachments, v_existing.attachments)) end;
end;
$function$;
alter function public.update_project_note_mentions(uuid,text,text[],uuid,jsonb) owner to postgres;
-- Reset every grantee introduced by CREATE/default privileges, including any
-- future role, before reproducing the exact reviewed allowlist.
do $acl$
declare v_grantee text;
begin
  for v_grantee in
    select distinct case when acl.grantee=0 then 'PUBLIC' else quote_ident(role.rolname) end
    from pg_proc p cross join lateral aclexplode(p.proacl) acl
    left join pg_roles role on role.oid=acl.grantee
    where p.oid='public.update_project_note_mentions(uuid,text,text[],uuid,jsonb)'::regprocedure
      and acl.grantee <> p.proowner
  loop
    execute 'revoke all on function public.update_project_note_mentions(uuid,text,text[],uuid,jsonb) from ' || v_grantee;
  end loop;
end;
$acl$;
grant execute on function public.update_project_note_mentions(uuid,text,text[],uuid,jsonb) to anon,authenticated;
comment on function public.update_project_note_mentions(uuid,text,text[],uuid,jsonb) is
  'Atomically replaces a human-authored note and its complete mention list, with optional detach-only attachments and one immutable idempotency proof for every edit.';

do $verify$
declare v_acl text[];
begin
  select array_agg(grantee::regrole::text || ':' || privilege_type || ':' || is_grantable::text order by grantee::regrole::text)
    into v_acl from aclexplode((select proacl from pg_proc where oid='public.update_project_note_mentions(uuid,text,text[],uuid,jsonb)'::regprocedure));
  if v_acl is distinct from array['anon:EXECUTE:false','authenticated:EXECUTE:false','postgres:EXECUTE:false'] then
    raise exception 'project note attachment migration final ACL mismatch' using errcode='55000';
  end if;
end;
$verify$;
notify pgrst, 'reload schema';
commit;
