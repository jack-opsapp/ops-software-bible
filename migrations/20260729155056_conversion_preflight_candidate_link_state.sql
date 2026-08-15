-- Bug 5468b3c6 — get_conversion_preflight offers MATCH candidates the commit
-- will refuse (already linked to another opportunity). Annotate each candidate
-- with "already_linked" so the client renders honestly instead of re-reading
-- rows and synthesizing blockers. Candidates are NOT dropped from the payload.
-- Applied from ops-web fix/conversion-rpc-accessible-migration 08547b63; drift
-- guard aborts loudly if the live definition does not match expectations.

do $migration$
declare
  v_def   text;
  v_hits  integer;
  v_needle constant text :=
$needle$'signals', case$needle$;
  v_replacement constant text :=
$replacement$-- Bug 5468b3c6 — link state, so the client never offers a MATCH the
          -- commit will reject and never has to guess by re-reading the row.
          -- Mirrors the commit's own rejection test: either mirror naming a
          -- different opportunity counts as linked, and an unparseable legacy
          -- value counts as linked because the commit treats it that way.
          'already_linked', (
            (
              p.opportunity_ref is not null
              and p.opportunity_ref is distinct from p_opportunity_id
            )
            or (
              nullif(btrim(coalesce(p.opportunity_id::text, '')), '') is not null
              and (
                private.try_parse_uuid(p.opportunity_id::text) is null
                or private.try_parse_uuid(p.opportunity_id::text)
                     is distinct from p_opportunity_id
              )
            )
          ),
          'signals', case$replacement$;
begin
  select pg_get_functiondef(p.oid)
    into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where p.proname = 'get_conversion_preflight'
     and n.nspname = 'public';

  if v_def is null then
    raise exception
      'get_conversion_preflight not found — refusing to patch';
  end if;

  if position('already_linked' in v_def) > 0 then
    raise exception
      'get_conversion_preflight already annotates candidates — nothing to apply';
  end if;

  -- The candidate payload is the only 'signals' key in this function.
  -- A count other than 1 means the function was rewritten upstream and
  -- this patch must be re-authored against the live source, never guessed.
  select count(*) into v_hits
    from regexp_matches(v_def, '''signals'', case', 'g');

  if v_hits <> 1 then
    raise exception
      'expected exactly 1 candidate signals block to patch, found % — re-read the live definition before applying',
      v_hits;
  end if;

  execute replace(v_def, v_needle, v_replacement);
end
$migration$;
