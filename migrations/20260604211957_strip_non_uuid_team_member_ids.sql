-- Strip non-uuid sentinels from team_member_ids (a text[]).
-- The crew-row drop handler historically wrote the synthetic "Special Events"
-- row id (formerly "__unassigned__") into team_member_ids; the text[] column
-- accepted it silently, but downstream `.in("id", team_member_ids)` against a
-- uuid id column throws `invalid input syntax for type uuid`. Repairs already-
-- corrupted rows, keeping only valid-uuid elements in their original order.

update public.project_tasks
   set team_member_ids = coalesce(
         (select array_agg(e order by ord)
            from unnest(team_member_ids) with ordinality as t(e, ord)
           where e ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
         '{}'::text[]
       )
 where team_member_ids is not null
   and exists (
         select 1 from unnest(team_member_ids) as e
          where e !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       );

update public.projects
   set team_member_ids = coalesce(
         (select array_agg(e order by ord)
            from unnest(team_member_ids) with ordinality as t(e, ord)
           where e ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
         '{}'::text[]
       )
 where team_member_ids is not null
   and exists (
         select 1 from unnest(team_member_ids) as e
          where e !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       );

update public.calendar_user_events
   set team_member_ids = coalesce(
         (select array_agg(e order by ord)
            from unnest(team_member_ids) with ordinality as t(e, ord)
           where e ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
         '{}'::text[]
       )
 where team_member_ids is not null
   and exists (
         select 1 from unnest(team_member_ids) as e
          where e !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       );
