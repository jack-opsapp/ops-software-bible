-- Catalog Setup Phase 5 private-function ACL hardening.
-- P5-20 source-of-truth draft only. Do not apply without explicit PM approval.
--
-- Why this exists:
-- P5-19R correctly preserves the Firebase-bridged iOS runtime path by granting
-- the anon DB role enough access to resolve OPS users through private helpers.
-- The live database still leaves most private-schema functions executable by
-- PUBLIC, which makes anon/authenticated/service_role effective EXECUTE broader
-- than the bridge needs.
--
-- Live audit reference:
-- - Project: ops-app / ijeekuhbatykdomumfjx / Postgres 17.6.
-- - private schema USAGE is explicit for anon, authenticated, and service_role.
-- - Most private functions have PUBLIC:EXECUTE, so anon/authenticated/service_role
--   inherit EXECUTE even when no direct role grant exists.
-- - public.catalog_setup_save(uuid,text,jsonb) is SECURITY INVOKER and calls
--   private.get_user_company_id(); its stock-event inserts also rely on the
--   public.catalog_stock_unit_events.created_by default private.get_current_user_id().
-- - Firebase bridge policies on user_roles, role_permissions, feature_flags,
--   feature_flag_overrides, catalog_setup_save_requests, and
--   catalog_stock_unit_events directly reference only private.get_current_user_id()
--   and private.get_user_company_id().
-- - Existing anon/PUBLIC RLS policies outside Catalog Setup still directly
--   reference a broader helper set. Those helpers stay executable by anon until
--   the Firebase bridge and those policies are redesigned together.
--
-- Important ACL behavior:
-- REVOKE EXECUTE FROM PUBLIC removes the inherited EXECUTE privilege for anon,
-- authenticated, and service_role unless those roles receive an explicit GRANT.

begin;

-- Keep schema access explicit and non-creatable for API roles. Do not grant
-- private schema USAGE to PUBLIC.
revoke usage on schema private from public;
revoke create on schema private from public;
revoke create on schema private from anon;
revoke create on schema private from authenticated;
revoke create on schema private from service_role;

grant usage on schema private to anon;
grant usage on schema private to authenticated;
grant usage on schema private to service_role;

-- Remove inherited and stale direct EXECUTE privileges from every current
-- private function signature. Grants below add back only required role access.
revoke execute on function private.catalog_categories_no_cycle()
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_can_assign_team_on_project(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_can_edit_project(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_can_view_project(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_has_permission(text, text)
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_in_project(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_is_admin()
  from public, anon, authenticated, service_role;
revoke execute on function private.current_user_scope_for(text)
  from public, anon, authenticated, service_role;
revoke execute on function private.get_current_user_id()
  from public, anon, authenticated, service_role;
revoke execute on function private.get_user_company_id()
  from public, anon, authenticated, service_role;
revoke execute on function private.is_ops_admin()
  from public, anon, authenticated, service_role;
revoke execute on function private.is_spec_operator()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_item_tags_delete()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_item_tags_insert()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_items_delete()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_items_insert()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_items_update()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_tags_delete()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_tags_insert()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_tags_update()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_units_delete()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_units_insert()
  from public, anon, authenticated, service_role;
revoke execute on function private.iv_inventory_units_update()
  from public, anon, authenticated, service_role;
revoke execute on function private.products_mirror_price()
  from public, anon, authenticated, service_role;
revoke execute on function private.project_table_project_id_from_text(text)
  from public, anon, authenticated, service_role;
revoke execute on function private.project_table_view_clean_name(text)
  from public, anon, authenticated, service_role;
revoke execute on function private.project_table_view_default_definition(public.project_views)
  from public, anon, authenticated, service_role;
revoke execute on function private.project_table_view_sanitize_definition(jsonb)
  from public, anon, authenticated, service_role;
revoke execute on function private.recompute_project_team_member_ids(uuid)
  from public, anon, authenticated, service_role;
revoke execute on function private.refresh_spec_board_snapshot()
  from public, anon, authenticated, service_role;
revoke execute on function private.resolve_uid()
  from public, anon, authenticated, service_role;
revoke execute on function private.seed_default_project_views_for_company()
  from public, anon, authenticated, service_role;
revoke execute on function private.sync_project_team_member_ids_from_tasks()
  from public, anon, authenticated, service_role;

-- Firebase-bridged Catalog Setup runtime helpers.
grant execute on function private.get_user_company_id()
  to anon, authenticated, service_role;
grant execute on function private.get_current_user_id()
  to anon, authenticated, service_role;

-- Existing Firebase bridge and PUBLIC-policy helpers. These are not widened by
-- this migration; they preserve current anon/authenticated runtime behavior
-- after PUBLIC EXECUTE is removed.
grant execute on function private.current_user_can_edit_project(uuid)
  to anon, authenticated;
grant execute on function private.current_user_can_view_project(uuid)
  to anon, authenticated;
grant execute on function private.current_user_has_permission(text, text)
  to anon, authenticated;
grant execute on function private.current_user_in_project(uuid)
  to anon, authenticated;
grant execute on function private.current_user_is_admin()
  to anon, authenticated;
grant execute on function private.current_user_scope_for(text)
  to anon, authenticated;
grant execute on function private.project_table_project_id_from_text(text)
  to anon, authenticated;
grant execute on function private.resolve_uid()
  to anon, authenticated;
grant execute on function private.is_spec_operator()
  to anon, authenticated;

-- Authenticated-only admin helper used by feature flag, role, admin, and
-- marketing/learning admin policies. Do not grant to anon.
grant execute on function private.is_ops_admin()
  to authenticated;

-- Service-only maintenance helper; keep it callable by server-side jobs without
-- restoring PUBLIC/anon/authenticated execution.
grant execute on function private.refresh_spec_board_snapshot()
  to service_role;

-- Functions intentionally left callable only by owner after this migration:
-- private.catalog_categories_no_cycle()
-- private.current_user_can_assign_team_on_project(uuid)
-- private.iv_inventory_item_tags_delete()
-- private.iv_inventory_item_tags_insert()
-- private.iv_inventory_items_delete()
-- private.iv_inventory_items_insert()
-- private.iv_inventory_items_update()
-- private.iv_inventory_tags_delete()
-- private.iv_inventory_tags_insert()
-- private.iv_inventory_tags_update()
-- private.iv_inventory_units_delete()
-- private.iv_inventory_units_insert()
-- private.iv_inventory_units_update()
-- private.products_mirror_price()
-- private.project_table_view_clean_name(text)
-- private.project_table_view_default_definition(public.project_views)
-- private.project_table_view_sanitize_definition(jsonb)
-- private.recompute_project_team_member_ids(uuid)
-- private.seed_default_project_views_for_company()
-- private.sync_project_team_member_ids_from_tasks()

-- Rollback plan, for PM-reviewed rollback only:
-- 1. Re-grant EXECUTE to PUBLIC on the private functions that had PUBLIC:EXECUTE
--    in the P5-20 live audit if this breaks a legacy runtime path.
-- 2. Restore direct anon/authenticated grants on
--    private.current_user_can_edit_project(uuid),
--    private.current_user_can_view_project(uuid), and
--    private.project_table_project_id_from_text(text) only if a rollback target
--    requires matching the exact pre-hardening ACL entries.
-- 3. Restore direct service_role EXECUTE on private.refresh_spec_board_snapshot()
--    if it was removed during any manual rollback attempt.
-- 4. Do not revoke anon USAGE on schema private until Firebase-bridged iOS no
--    longer relies on anon DB-role RLS helper execution.

commit;
