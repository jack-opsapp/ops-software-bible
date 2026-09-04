-- Bug 9f4aeaf8 — deck design save-loss.
--
-- ============================================================================
-- PENDING: NOT YET APPLIED TO PROD. This file is checked in ahead of the apply
-- so the SQL can be reviewed. On apply, read the stamped ledger version back
-- from supabase_migrations.schema_migrations and RENAME this file to
-- <ledger_version>_deck_design_geometry_regression_log.sql per migrations/README.md.
-- Verify by OBJECT (the four probes at the tail), never by ledger row.
-- ============================================================================
--
-- Observation only: records any UPDATE that removes deck geometry, so silent
-- geometry loss becomes visible instead of being discovered from a customer
-- report. The client-side correctness fixes for this bug are complete on their
-- own; what the server has never given us is any way to SEE the loss.
--
-- Blocks nothing on purpose. A hard "refuse to empty a deck" rule would break
-- clearDesign(), which is a real user action. Observe first; if the log shows
-- emptying that no user initiated, escalate to a block with the evidence.
--
-- Cost: zero. One small table plus one trigger on a table that takes a handful
-- of writes per day. No compute tier change, no new service, a few KB/year at
-- current volume.

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

-- Diagnostic table: readable within the company, never written by clients.
drop policy if exists company_isolation on public.deck_design_geometry_regressions;
create policy company_isolation
  on public.deck_design_geometry_regressions
  for select
  using (company_id = (select private.get_user_company_id()));

revoke insert, update, delete on public.deck_design_geometry_regressions from anon, authenticated;
grant select on public.deck_design_geometry_regressions to anon, authenticated;

-- Counts geometry across BOTH drawing shapes. A single-level deck carries
-- vertices/edges at the root; a multi-level deck carries them per level and
-- leaves the root arrays empty, so counting only the root would make every
-- multi-level deck permanently invisible to this log.
--
-- Every read is type-guarded rather than trusting the shape: jsonb_array_length
-- raises on a non-array, and a raise inside a BEFORE/AFTER trigger would fail
-- the user's write. A diagnostic must never be able to do that.
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
  -- The log is never worth a user's save. Anything unexpected in here is
  -- swallowed and the write proceeds.
  when others then
    return null;
end;
$$;

drop trigger if exists deck_designs_log_geometry_regression on public.deck_designs;
create trigger deck_designs_log_geometry_regression
  after update of drawing_data on public.deck_designs
  for each row
  execute function private.log_deck_design_geometry_regression();

-- ---------------------------------------------------------------------------
-- Post-apply probes — all four must pass. Verify by OBJECT, never by ledger row.
-- ---------------------------------------------------------------------------
-- 1. table exists and is empty
--    select count(*) from public.deck_design_geometry_regressions;          -- expect 0
--
-- 2. trigger is attached
--    select tgname from pg_trigger
--     where tgrelid = 'public.deck_designs'::regclass
--       and tgname = 'deck_designs_log_geometry_regression';                -- expect 1 row
--
-- 3. clients cannot write it
--    select grantee, privilege_type from information_schema.role_table_grants
--     where table_schema='public' and table_name='deck_design_geometry_regressions'
--       and grantee in ('anon','authenticated');                            -- expect SELECT only
--
-- 4. the existing deck write path still works (rollback probe — writes nothing)
--    begin;
--      update public.deck_designs set title = title where id = (select id from public.deck_designs limit 1);
--      select count(*) from public.deck_design_geometry_regressions;        -- expect 0 (no geometry change)
--    rollback;
--
-- Rollback:
--    drop trigger if exists deck_designs_log_geometry_regression on public.deck_designs;
--    drop function if exists private.log_deck_design_geometry_regression();
--    drop function if exists private.deck_design_geometry_counts(jsonb);
--    -- keep the table; it holds evidence.
