-- compose_task_scopes — deterministic visit composition for task groups.
-- Spec: ops-software-bible/specs/2026-09-01-task-groups-design.md §6.
--
-- Given candidate scopes for one company (caller order preserved), partition them into visits:
--   1. Resolve every candidate's task type inside p_company_id (not soft-deleted); an unknown or
--      foreign type raises compose_unknown_task_type.
--   2. Build directed dependency edges among the candidate types only: X -> Y when candidate Y's
--      type declares a dependency on candidate X's type. Resolve transitively within that set.
--   3. A candidate type some other candidate type depends on (directly or transitively) is a
--      predecessor visit: its own visit, emitted in topological order, ties broken by input order.
--   4. Every remaining candidate is a leaf. Leaves partition by crew compatibility only: an empty
--      default crew is compatible with anything, two non-empty crews are compatible iff equal as
--      sets. Assignment is greedy in input order into the first compatible open group; a group's
--      effective crew is the first non-empty crew placed in it. Differing predecessor sets never
--      separate leaves — a visit's after_task_type_ids is the union of its members' candidate
--      predecessors, which is how the scheduler applies the max-of-constraints rule.
--   5. primary_task_type_id is the visit's first member in input order; candidates that repeat a
--      type stay as separate scopes of the same visit. kind is 'single' for a one-scope visit and
--      'group' otherwise. Output order: predecessor visits (topological) then leaf visits.
--   6. Every visit carries a human-readable reason. Same input => byte-identical output.
--
-- Security follows the codebase convention for company-scoped callables: user callers must pass
-- their own company (private.get_user_company_id()); the service_role context is exempt, as in the
-- read_agent_*_as_system / create_task_with_event_as_system family.
create or replace function public.compose_task_scopes(p_company_id uuid, p_candidates jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_candidates      jsonb := coalesce(p_candidates, '[]'::jsonb);
  v_parsed          jsonb;
  v_graph           jsonb;
  v_types           jsonb;
  v_cands           jsonb;
  v_count           integer;
  v_pending         text[] := array[]::text[];
  v_pred_order      text[] := array[]::text[];
  v_ready           text;
  v_type_id         text;
  v_group_crew      jsonb := '[]'::jsonb;
  v_group_members   jsonb := '[]'::jsonb;
  v_group_index     integer;
  v_compatible      boolean;
  v_crew            jsonb;
  v_pos             integer;
  v_g               integer;
  v_leaf_groups     integer;
  v_members         jsonb;
  v_scopes          jsonb;
  v_after           jsonb;
  v_visits          jsonb := '[]'::jsonb;
  v_names           text;
  v_dependent_names text;
  v_ancestor_names  text;
  v_primary         text;
  v_reason          text;
begin
  if p_company_id is null then
    raise exception 'compose_company_id_required' using errcode = '22023';
  end if;

  if auth.role() is distinct from 'service_role'
     and p_company_id is distinct from private.get_user_company_id() then
    raise exception 'compose_company_scope_mismatch' using errcode = '42501';
  end if;

  if jsonb_typeof(v_candidates) <> 'array' then
    raise exception 'compose_candidates_array_required' using errcode = '22023';
  end if;

  select count(*)
    into v_count
    from jsonb_array_elements(v_candidates) as c(elem)
   where jsonb_typeof(c.elem) <> 'object'
      or nullif(btrim(coalesce(c.elem->>'task_type_id', '')), '') is null;

  if v_count > 0 then
    raise exception 'compose_candidate_task_type_required' using errcode = '22023';
  end if;

  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'idx', c.ord,
             'task_type_id', (c.elem->>'task_type_id')::uuid,
             'note', c.elem->>'note',
             'source_line_item_id', c.elem->>'source_line_item_id'
           ) order by c.ord), '[]'::jsonb)
      into v_parsed
      from jsonb_array_elements(v_candidates) with ordinality as c(elem, ord);
  exception when invalid_text_representation then
    raise exception 'compose_candidate_task_type_invalid' using errcode = '22023';
  end;

  select count(*)
    into v_count
    from jsonb_array_elements(v_parsed) as c(elem)
   where not exists (select 1
                       from public.task_types tt
                      where tt.id = (c.elem->>'task_type_id')::uuid
                        and tt.company_id = p_company_id
                        and tt.deleted_at is null);

  if v_count > 0 then
    raise exception 'compose_unknown_task_type' using errcode = '23503';
  end if;

  if jsonb_array_length(v_parsed) = 0 then
    return jsonb_build_object('visits', '[]'::jsonb);
  end if;

  with recursive
  candidate as (
    select (c.elem->>'idx')::integer as idx,
           (c.elem->>'task_type_id')::uuid as task_type_id,
           c.elem->>'note' as note,
           c.elem->>'source_line_item_id' as source_line_item_id
      from jsonb_array_elements(v_parsed) as c(elem)
  ),
  resolved as (
    select cand.idx,
           cand.task_type_id,
           cand.note,
           cand.source_line_item_id,
           tt.display,
           coalesce(tt.default_team_member_ids, array[]::text[]) as crew,
           tt.dependencies
      from candidate cand
      join public.task_types tt
        on tt.id = cand.task_type_id
       and tt.company_id = p_company_id
       and tt.deleted_at is null
  ),
  type_info as (
    select distinct on (r.task_type_id)
           r.task_type_id,
           r.display,
           r.crew,
           r.dependencies,
           r.idx as first_idx
      from resolved r
     order by r.task_type_id, r.idx
  ),
  edge as (
    select distinct
           before_type.task_type_id as before_id,
           after_type.task_type_id as after_id
      from type_info after_type
      cross join lateral jsonb_array_elements(
             case when jsonb_typeof(after_type.dependencies) = 'array'
                  then after_type.dependencies
                  else '[]'::jsonb
             end) as d(dep)
      join type_info before_type
        on jsonb_typeof(d.dep) = 'object'
       and before_type.task_type_id = (
             case when d.dep->>'depends_on_task_type_id'
                       ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                  then (d.dep->>'depends_on_task_type_id')::uuid
             end)
     where before_type.task_type_id <> after_type.task_type_id
  ),
  reach as (
    select e.before_id, e.after_id
      from edge e
    union
    select e.before_id, r.after_id
      from edge e
      join reach r on r.before_id = e.after_id
  ),
  ordered_reach as (
    select r.before_id, r.after_id
      from reach r
     where r.before_id <> r.after_id
  ),
  type_final as (
    select ti.task_type_id,
           ti.display,
           ti.first_idx,
           to_jsonb(ti.crew) as crew,
           exists (select 1 from ordered_reach orr where orr.before_id = ti.task_type_id) as is_predecessor,
           coalesce((select jsonb_agg(to_jsonb(anc.task_type_id::text) order by anc.first_idx)
                       from ordered_reach orr
                       join type_info anc on anc.task_type_id = orr.before_id
                      where orr.after_id = ti.task_type_id), '[]'::jsonb) as ancestor_ids,
           coalesce((select jsonb_agg(to_jsonb(dep.task_type_id::text) order by dep.first_idx)
                       from ordered_reach orr
                       join type_info dep on dep.task_type_id = orr.after_id
                      where orr.before_id = ti.task_type_id), '[]'::jsonb) as dependent_ids
      from type_info ti
  )
  select jsonb_build_object(
           'candidates', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'idx', r.idx,
                                   'task_type_id', r.task_type_id::text,
                                   'note', r.note,
                                   'source_line_item_id', r.source_line_item_id
                                 ) order by r.idx), '[]'::jsonb)
                            from resolved r),
           'types', (select coalesce(jsonb_object_agg(tf.task_type_id::text, jsonb_build_object(
                              'display', tf.display,
                              'first_idx', tf.first_idx,
                              'crew', tf.crew,
                              'is_predecessor', tf.is_predecessor,
                              'ancestor_ids', tf.ancestor_ids,
                              'dependent_ids', tf.dependent_ids
                            )), '{}'::jsonb)
                       from type_final tf)
         )
    into v_graph;

  v_cands := v_graph->'candidates';
  v_types := v_graph->'types';

  -- Predecessor visits, topologically ordered with input order as the tie-break.
  select coalesce(array_agg(t.key order by (t.value->>'first_idx')::integer), array[]::text[])
    into v_pending
    from jsonb_each(v_types) as t(key, value)
   where (t.value->>'is_predecessor')::boolean;

  while array_length(v_pending, 1) is not null loop
    v_ready := null;
    foreach v_type_id in array v_pending loop
      if not exists (select 1
                       from jsonb_array_elements_text(v_types->v_type_id->'ancestor_ids') as a(anc)
                      where a.anc = any (v_pending)) then
        v_ready := v_type_id;
        exit;
      end if;
    end loop;
    if v_ready is null then
      -- Dependency cycle among the candidates: fall back to input order, stay deterministic.
      v_ready := v_pending[1];
    end if;
    v_pred_order := v_pred_order || v_ready;
    v_pending := array_remove(v_pending, v_ready);
  end loop;

  -- Leaf visits, greedy crew-compatible grouping in input order.
  for v_pos in 0 .. jsonb_array_length(v_cands) - 1 loop
    v_type_id := v_cands->v_pos->>'task_type_id';
    continue when (v_types->v_type_id->>'is_predecessor')::boolean;

    v_crew := v_types->v_type_id->'crew';
    v_group_index := null;

    for v_g in 0 .. jsonb_array_length(v_group_crew) - 1 loop
      select jsonb_array_length(v_group_crew->v_g) = 0
          or jsonb_array_length(v_crew) = 0
          or ((select coalesce(array_agg(distinct g.member order by g.member), array[]::text[])
                 from jsonb_array_elements_text(v_group_crew->v_g) as g(member))
              = (select coalesce(array_agg(distinct c.member order by c.member), array[]::text[])
                   from jsonb_array_elements_text(v_crew) as c(member)))
        into v_compatible;
      if v_compatible then
        v_group_index := v_g;
        exit;
      end if;
    end loop;

    if v_group_index is null then
      v_group_crew := v_group_crew || jsonb_build_array(v_crew);
      v_group_members := v_group_members || jsonb_build_array(jsonb_build_array(v_pos));
    else
      if jsonb_array_length(v_group_crew->v_group_index) = 0 and jsonb_array_length(v_crew) > 0 then
        v_group_crew := jsonb_set(v_group_crew, array[v_group_index::text], v_crew);
      end if;
      v_group_members := jsonb_set(v_group_members, array[v_group_index::text],
                                   (v_group_members->v_group_index) || jsonb_build_array(v_pos));
    end if;
  end loop;

  foreach v_type_id in array v_pred_order loop
    select coalesce(jsonb_agg(jsonb_build_object(
             'task_type_id', c.elem->>'task_type_id',
             'note', c.elem->'note',
             'source_line_item_id', c.elem->'source_line_item_id'
           ) order by (c.elem->>'idx')::integer), '[]'::jsonb)
      into v_scopes
      from jsonb_array_elements(v_cands) as c(elem)
     where c.elem->>'task_type_id' = v_type_id;

    v_after := v_types->v_type_id->'ancestor_ids';
    v_names := v_types->v_type_id->>'display';

    select string_agg(v_types->d.dep->>'display', ', ' order by (v_types->d.dep->>'first_idx')::integer)
      into v_dependent_names
      from jsonb_array_elements_text(v_types->v_type_id->'dependent_ids') as d(dep);

    v_reason := v_names || ' must finish before ' || v_dependent_names;

    if jsonb_array_length(v_after) > 0 then
      select string_agg(v_types->a.anc->>'display', ', ' order by (v_types->a.anc->>'first_idx')::integer)
        into v_ancestor_names
        from jsonb_array_elements_text(v_after) as a(anc);
      v_reason := v_reason || ' — after ' || v_ancestor_names;
    end if;

    v_visits := v_visits || jsonb_build_array(jsonb_build_object(
      'kind', case when jsonb_array_length(v_scopes) = 1 then 'single' else 'group' end,
      'primary_task_type_id', v_type_id,
      'scopes', v_scopes,
      'after_task_type_ids', v_after,
      'reason', v_reason
    ));
  end loop;

  v_leaf_groups := jsonb_array_length(v_group_members);

  for v_g in 0 .. v_leaf_groups - 1 loop
    v_members := v_group_members->v_g;

    select coalesce(jsonb_agg(jsonb_build_object(
             'task_type_id', v_cands->(m.pos::integer)->>'task_type_id',
             'note', v_cands->(m.pos::integer)->'note',
             'source_line_item_id', v_cands->(m.pos::integer)->'source_line_item_id'
           ) order by m.ord), '[]'::jsonb)
      into v_scopes
      from jsonb_array_elements_text(v_members) with ordinality as m(pos, ord);

    v_primary := v_cands->((v_members->>0)::integer)->>'task_type_id';

    select coalesce(jsonb_agg(to_jsonb(x.anc) order by (v_types->x.anc->>'first_idx')::integer), '[]'::jsonb)
      into v_after
      from (select distinct a.anc
              from jsonb_array_elements_text(v_members) as m(pos)
              cross join lateral jsonb_array_elements_text(
                    v_types->(v_cands->(m.pos::integer)->>'task_type_id')->'ancestor_ids') as a(anc)) x;

    select string_agg(y.display, ', ' order by y.first_idx)
      into v_names
      from (select distinct
                   v_types->(v_cands->(m.pos::integer)->>'task_type_id')->>'display' as display,
                   (v_types->(v_cands->(m.pos::integer)->>'task_type_id')->>'first_idx')::integer as first_idx
              from jsonb_array_elements_text(v_members) as m(pos)) y;

    if jsonb_array_length(v_scopes) > 1 then
      v_reason := v_names || ' share a crew and none depends on another — one visit';
    elsif v_leaf_groups > 1 then
      v_reason := v_names || ' has its own crew — separate visit';
    else
      v_reason := v_names || ' — one visit';
    end if;

    if jsonb_array_length(v_after) > 0 then
      select string_agg(v_types->a.anc->>'display', ', ' order by (v_types->a.anc->>'first_idx')::integer)
        into v_ancestor_names
        from jsonb_array_elements_text(v_after) as a(anc);
      v_reason := v_reason || ' after ' || v_ancestor_names;
    end if;

    v_visits := v_visits || jsonb_build_array(jsonb_build_object(
      'kind', case when jsonb_array_length(v_scopes) = 1 then 'single' else 'group' end,
      'primary_task_type_id', v_primary,
      'scopes', v_scopes,
      'after_task_type_ids', v_after,
      'reason', v_reason
    ));
  end loop;

  return jsonb_build_object('visits', v_visits);
end;
$function$;

comment on function public.compose_task_scopes(uuid, jsonb) is
  'Deterministic task-group composition (spec 2026-09-01 §6): partitions candidate scopes into visits — dependency predecessors as sequenced visits, remaining leaves grouped by crew compatibility — with after_task_type_ids and an explainable reason per visit.';

revoke all on function public.compose_task_scopes(uuid, jsonb) from public;
grant execute on function public.compose_task_scopes(uuid, jsonb) to anon, authenticated, service_role, postgres;
