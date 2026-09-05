-- public.execute_client_merge_guarded has NEVER succeeded in production.
--
-- site_visits.company_id is TEXT while the RPC's p_company_id is UUID, so both
-- site_visits statements raise `42883 operator does not exist: text = uuid`
-- and abort the whole merge. Proven by direct probe:
--   select count(*) from public.site_visits
--    where company_id = 'a612edc0-...'::uuid;   -> 42883
--
-- Same defect family as the Phase C bilateral handoff fixed 2026-09-03. Per that
-- precedent the UUID side is cast to text, never the column — casting the column
-- would defeat its index and can fail on malformed rows.
--
-- Only site_visits is affected. Of the 17 tables this function updates, exactly
-- three have a TEXT company_id (site_visits, portal_messages, portal_tokens) and
-- the portal_* statements do not compare company_id at all. The literal
-- `company_id = p_company_id;` appears 26 times in this function, so the two
-- target statements are anchored on their unique UPDATE lines rather than
-- replaced blindly.

do $mig$
declare
  v_def text;
  v_new text;
  v_before int;
  v_after int;
begin
  select pg_get_functiondef(p.oid)
    into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'execute_client_merge_guarded';

  if v_def is null then
    raise exception 'execute_client_merge_guarded not found';
  end if;

  select count(*) into v_before
    from regexp_matches(v_def, 'p_company_id::text', 'g');
  if v_before <> 0 then
    raise exception 'already patched (% occurrences of p_company_id::text)', v_before;
  end if;

  v_new := regexp_replace(
    v_def,
    '(update public\.site_visits set client_ref = p_winner_id\s+where client_ref = p_loser_id and company_id = p_company_id);',
    '\1::text;',
    'g'
  );
  v_new := regexp_replace(
    v_new,
    '(update public\.site_visits set client_id = v_winner_text\s+where client_id = v_loser_text and company_id = p_company_id);',
    '\1::text;',
    'g'
  );

  select count(*) into v_after
    from regexp_matches(v_new, 'p_company_id::text', 'g');
  if v_after <> 2 then
    raise exception 'expected exactly 2 patched predicates, got %', v_after;
  end if;

  -- the only difference must be the two added casts
  if length(v_new) <> length(v_def) + 12 then
    raise exception 'unexpected edit size: % vs %', length(v_new), length(v_def);
  end if;

  execute v_new;
end $mig$;

-- post-condition: the comparison the function makes must now succeed
do $verify$
declare v_n int;
begin
  select count(*) into v_n
    from public.site_visits
   where company_id = 'a612edc0-5c18-4c4d-af97-55b9410dd077'::uuid::text;
  raise notice 'site_visits reachable by text-cast company_id: %', v_n;
end $verify$;
