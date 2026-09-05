-- Second blocker in public.execute_client_merge_guarded, found after the
-- text=uuid cast fix (20260904190224) let execution reach it.
--
-- The function issues `update public.project_table_rows set client_id = ...`,
-- but project_table_rows is a READ-ONLY VIEW (relkind='v', zero triggers) over
-- projects LEFT JOIN clients. Postgres raises 55000 "cannot update view
-- project_table_rows" and the whole merge aborts. Proven by a rolled-back
-- dry run of the Allan Chapman client merge as service_role.
--
-- The statement is also REDUNDANT: the view's client_id column IS
-- projects.client_id, which the function already re-points a few statements
-- earlier ("projects.client_id (enforced FK)"). By the time control reached
-- here, the rows it looked for could not exist.
--
-- Removed along with its manifest entry. No consumer reads that key
-- (grepped ops-web/src for manifest consumers: none).

do $mig$
declare
  v_def text;
  v_new text;
  v_hits int;
begin
  select pg_get_functiondef(p.oid)
    into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'execute_client_merge_guarded';

  if v_def is null then
    raise exception 'execute_client_merge_guarded not found';
  end if;

  select count(*) into v_hits
    from regexp_matches(v_def, 'update public\.project_table_rows', 'g');
  if v_hits <> 1 then
    raise exception 'expected exactly 1 project_table_rows update, found %', v_hits;
  end if;

  v_new := regexp_replace(
    v_def,
    '  -- project_table_rows\.client_id \(unenforced\)\.\s+update public\.project_table_rows set client_id = p_winner_id\s+where client_id = p_loser_id and company_id = p_company_id;\s+get diagnostics v_n = row_count;\s+v_manifest := v_manifest \|\| jsonb_build_object\(''project_table_rows'', v_n\);',
    '  -- project_table_rows is a READ-ONLY VIEW over projects LEFT JOIN clients;'
    || chr(10) ||
    '  -- its client_id IS projects.client_id, already re-pointed above. The UPDATE'
    || chr(10) ||
    '  -- that stood here raised 55000 and aborted every merge.'
    || chr(10) ||
    '  null;',
    'g'
  );

  if v_new = v_def then
    raise exception 'project_table_rows block did not match; nothing replaced';
  end if;

  select count(*) into v_hits
    from regexp_matches(v_new, 'update public\.project_table_rows', 'g');
  if v_hits <> 0 then
    raise exception 'view update survived the edit';
  end if;

  -- the real projects re-point must still be there
  select count(*) into v_hits
    from regexp_matches(v_new, 'update public\.projects set client_id = p_winner_id', 'g');
  if v_hits < 1 then
    raise exception 'projects.client_id re-point missing after edit';
  end if;

  -- and the site_visits casts from the prior fix must survive
  select count(*) into v_hits
    from regexp_matches(v_new, 'p_company_id::text', 'g');
  if v_hits <> 2 then
    raise exception 'site_visits casts lost: %', v_hits;
  end if;

  execute v_new;
end $mig$;
