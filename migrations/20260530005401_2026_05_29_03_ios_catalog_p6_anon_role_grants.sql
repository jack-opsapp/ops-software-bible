-- Phase 6 tables/RPCs were granted to `authenticated` only. The OPS iOS app
-- connects to PostgREST as the `anon` Postgres role (the user identity rides in
-- the JWT `sub`, so auth.uid()/RLS and the RPCs' internal company + permission
-- checks still apply per-row and per-caller). Phase 5 catalog objects grant
-- `anon`; Phase 6 did not, so the entire Phase 6 layer was unreachable from the
-- app (HTTP 401 "permission denied" on company_inventory_settings, etc.).
-- This change is additive and does NOT weaken isolation: RLS policies and the
-- SECURITY INVOKER RPC guards remain the access control; this only lets the
-- role the app actually uses reach these objects, mirroring `authenticated`.

grant select, insert, update on public.company_inventory_settings        to anon;
grant select, insert, update on public.project_material_demands          to anon;
grant select, insert, update on public.task_material_allocations         to anon;
grant select, insert         on public.project_material_snapshots        to anon;
grant select, insert         on public.project_material_snapshot_items   to anon;
grant select, insert, update on public.task_material_consumption_requests to anon;

grant execute on function public.set_company_inventory_mode(uuid, text)                  to anon;
grant execute on function public.accept_estimate_to_job(uuid, text)                      to anon;
grant execute on function public.complete_project_task(uuid, text, jsonb)                to anon;
