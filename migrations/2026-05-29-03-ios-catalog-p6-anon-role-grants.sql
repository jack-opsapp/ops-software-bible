-- 2026-05-29-03-ios-catalog-p6-anon-role-grants.sql
-- Applied to ops-app (ijeekuhbatykdomumfjx) as migration
-- 2026_05_29_03_ios_catalog_p6_anon_role_grants.
--
-- WHY: Phase 6 tables/RPCs were granted to `authenticated` only. The OPS iOS
-- app connects to PostgREST as the `anon` Postgres role (the user identity
-- rides in the JWT `sub`, so auth.uid()/RLS and the RPCs' internal company +
-- permission checks still apply per-row and per-caller). Phase 5 catalog
-- objects (catalog_setup_save, catalog_product_option_mappings,
-- catalog_stock_units, move_opportunity_stage) grant `anon`; Phase 6 did not,
-- so the entire Phase 6 layer was unreachable from the app — runtime returned
-- HTTP 401 "permission denied for table company_inventory_settings" and the
-- inventory-mode toggle showed "SYS :: MODE UNAVAILABLE". accept_estimate_to_job
-- and complete_project_task would have failed identically.
--
-- This change is additive and does NOT weaken isolation: RLS policies and the
-- SECURITY INVOKER RPC guards remain the access control. This only lets the
-- role the app actually uses reach these objects, mirroring the existing
-- `authenticated` grants.
--
-- Found during the Phase 6 iOS runtime walkthrough on 2026-05-29 (MAVERICK
-- PROJECTS LTD test company). The migration smoke tests passed because they set
-- request.jwt.claims to role=authenticated, which masked the anon gap.

grant select, insert, update on public.company_inventory_settings         to anon;
grant select, insert, update on public.project_material_demands           to anon;
grant select, insert, update on public.task_material_allocations          to anon;
grant select, insert         on public.project_material_snapshots         to anon;
grant select, insert         on public.project_material_snapshot_items    to anon;
grant select, insert, update on public.task_material_consumption_requests to anon;

grant execute on function public.set_company_inventory_mode(uuid, text)   to anon;
grant execute on function public.accept_estimate_to_job(uuid, text)       to anon;
grant execute on function public.complete_project_task(uuid, text, jsonb) to anon;
