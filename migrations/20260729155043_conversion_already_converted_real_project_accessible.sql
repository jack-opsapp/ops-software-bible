-- Bug ced5b3cb — the idempotent already-converted branch of
-- convert_opportunity_to_project returns a REAL project id while hardcoding
-- 'project_accessible', false. Patch it surgically to compute the real answer
-- (actorless service callers keep false). Applied from ops-web
-- fix/conversion-rpc-accessible-migration 08547b63; drift guard aborts loudly
-- if the live definition does not contain the needle exactly once.

do $migration$
declare
  v_def   text;
  v_hits  integer;
  v_needle constant text :=
$needle$'linked_existing', v_existing_linked_existing,
      'won', v_opp.stage = 'won',
      'project_accessible', false
    );
  end if$needle$;
  v_replacement constant text :=
$replacement$'linked_existing', v_existing_linked_existing,
      'won', v_opp.stage = 'won',
      -- Bug ced5b3cb — this branch returns a REAL project id, so it must
      -- return a REAL access answer. Actorless service callers keep false:
      -- there is no actor whose visibility could be evaluated.
      'project_accessible', case
        when v_actor_user_id is null then false
        else coalesce(
          private.user_can_view_project(v_actor_user_id, v_link_to_project_id),
          false
        )
      end
    );
  end if$replacement$;
begin
  select pg_get_functiondef(p.oid)
    into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where p.proname = 'convert_opportunity_to_project'
     and n.nspname = 'public';

  if v_def is null then
    raise exception
      'convert_opportunity_to_project not found — refusing to patch';
  end if;

  -- Idempotency + drift guard in one. Zero hits means either the patch is
  -- already applied or the branch was rewritten upstream; both demand a
  -- human re-read of the live source, never a silent skip.
  select count(*) into v_hits
    from regexp_matches(v_def, regexp_replace(v_needle, '([().*+?\[\]{}|^$\\])', '\\\1', 'g'), 'g');

  if v_hits <> 1 then
    raise exception
      'expected exactly 1 already-converted return to patch, found % — re-read the live definition before applying',
      v_hits;
  end if;

  execute replace(v_def, v_needle, v_replacement);
end
$migration$;
