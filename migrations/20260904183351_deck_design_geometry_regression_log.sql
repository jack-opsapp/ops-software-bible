create table if not exists public.deck_design_geometry_regressions (
  id               uuid primary key default gen_random_uuid(),
  deck_design_id   uuid not null,
  company_id       uuid,
  old_vertex_count integer not null,
  new_vertex_count integer not null,
  old_edge_count   integer not null,
  new_edge_count   integer not null,
  old_updated_at   timestamptz,
  new_updated_at   timestamptz,
  observed_at      timestamptz not null default now()
);

create index if not exists deck_design_geometry_regressions_design_idx
  on public.deck_design_geometry_regressions (deck_design_id, observed_at desc);

alter table public.deck_design_geometry_regressions enable row level security;

drop policy if exists company_isolation on public.deck_design_geometry_regressions;
create policy company_isolation
  on public.deck_design_geometry_regressions
  for select
  using (company_id = (select private.get_user_company_id()));

revoke insert, update, delete on public.deck_design_geometry_regressions from anon, authenticated;
grant select on public.deck_design_geometry_regressions to anon, authenticated;

create or replace function private.deck_design_geometry_counts(p_drawing jsonb)
returns table (vertex_count integer, edge_count integer)
language sql
immutable
set search_path = pg_catalog
as $$
  select
    (case when jsonb_typeof(p_drawing -> 'vertices') = 'array'
          then jsonb_array_length(p_drawing -> 'vertices') else 0 end)
    + coalesce((
        select sum(case when jsonb_typeof(lvl -> 'vertices') = 'array'
                        then jsonb_array_length(lvl -> 'vertices') else 0 end)
        from jsonb_array_elements(
               case when jsonb_typeof(p_drawing -> 'levels') = 'array'
                    then p_drawing -> 'levels' else '[]'::jsonb end
             ) as lvl
      ), 0)::integer,
    (case when jsonb_typeof(p_drawing -> 'edges') = 'array'
          then jsonb_array_length(p_drawing -> 'edges') else 0 end)
    + coalesce((
        select sum(case when jsonb_typeof(lvl -> 'edges') = 'array'
                        then jsonb_array_length(lvl -> 'edges') else 0 end)
        from jsonb_array_elements(
               case when jsonb_typeof(p_drawing -> 'levels') = 'array'
                    then p_drawing -> 'levels' else '[]'::jsonb end
             ) as lvl
      ), 0)::integer;
$$;

create or replace function private.log_deck_design_geometry_regression()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_old_v integer;
  v_new_v integer;
  v_old_e integer;
  v_new_e integer;
begin
  select vertex_count, edge_count into v_old_v, v_old_e
    from private.deck_design_geometry_counts(old.drawing_data);
  select vertex_count, edge_count into v_new_v, v_new_e
    from private.deck_design_geometry_counts(new.drawing_data);

  if v_new_v < v_old_v or v_new_e < v_old_e then
    insert into public.deck_design_geometry_regressions (
      deck_design_id, company_id,
      old_vertex_count, new_vertex_count,
      old_edge_count, new_edge_count,
      old_updated_at, new_updated_at
    ) values (
      old.id, new.company_id,
      v_old_v, v_new_v,
      v_old_e, v_new_e,
      old.updated_at, new.updated_at
    );
  end if;

  return null;
exception
  when others then
    return null;
end;
$$;

drop trigger if exists deck_designs_log_geometry_regression on public.deck_designs;
create trigger deck_designs_log_geometry_regression
  after update of drawing_data on public.deck_designs
  for each row
  execute function private.log_deck_design_geometry_regression();
