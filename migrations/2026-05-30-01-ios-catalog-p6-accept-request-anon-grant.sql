-- Migration: iOS Catalog P6 — complete anon execute/grant parity for the
--            estimate-acceptance + task-completion surface
-- Date: 2026-05-30
--
-- Context: The iOS app authenticates against Supabase as the `anon` Postgres role
--   (the user identity rides in the JWT, which private.get_current_user_id() /
--   private.get_user_company_id() resolve, but PostgREST still executes the
--   request under `anon`). The prior P6 anon-role-grants migration
--   (2026-05-29-03) granted `anon` the P6 write TABLES and EXECUTE on the public
--   RPCs (accept_estimate_to_job, complete_project_task, set_company_inventory_mode),
--   but it missed, for the anon role specifically:
--
--   1. The public.accept_estimate_to_job_requests TABLE (granted to
--      `authenticated` only). accept_estimate_to_job() is SECURITY INVOKER and its
--      first write inserts into that table as the caller -> runtime failure
--      "permission denied for table accept_estimate_to_job_requests".
--
--   2. EXECUTE on the entire private helper-function layer the P6 RPCs call
--      (granted to `authenticated` only by the function-ACL-hardening pass). The
--      public RPCs are SECURITY INVOKER and call these helpers as the caller, so
--      acceptance failed with "permission denied for function
--      sync_accepted_estimate_project_tasks" (and the task-completion +
--      auto-bug-logging paths would fail identically).
--
-- This brings `anon` to full execute/grant parity with `authenticated` for the
-- acceptance + completion surface. It is additive and does not weaken isolation:
-- RLS policies and the in-function company + permission guards remain the access
-- control; EXECUTE only lets the role the app actually uses reach these objects.
-- Found during the P6 iOS runtime walkthrough on 2026-05-30 (MAVERICK PROJECTS
-- LTD test company); migration smoke tests masked the gap because they set
-- request.jwt.claims to role=authenticated.
--
-- Idempotent: GRANT is repeatable; re-running is safe.

-- (1) Missing table grant — bring in line with the other P6 write tables.
grant select, insert, update on table public.accept_estimate_to_job_requests to anon;

-- (2) Missing EXECUTE on the private helper functions in the P6 call trees.
grant execute on function private.catalog_variant_available_stock_summary(uuid, uuid)                       to anon;
grant execute on function private.consume_task_materials_for_completed_task(uuid, text, jsonb)              to anon;
grant execute on function private.current_user_can_complete_task_material_consumption(uuid, uuid)           to anon;
grant execute on function private.current_user_can_write_project_material_workflow(uuid)                    to anon;
grant execute on function private.is_ops_admin()                                                            to anon;
grant execute on function private.persist_catalog_mapping_notifications_from_missing_mappings(uuid, jsonb)  to anon;
grant execute on function private.persist_estimate_material_booking_projection(uuid, uuid)                  to anon;
grant execute on function private.resolve_catalog_variant_for_material_demand(uuid, uuid, uuid, jsonb, jsonb) to anon;
grant execute on function private.resolve_estimate_material_demand_plan(uuid, uuid)                          to anon;
grant execute on function private.sync_accepted_estimate_project_tasks(uuid)                                to anon;
grant execute on function private.try_parse_uuid(text)                                                      to anon;

-- (3) record_auto_bug — the app's auto-bug logger, also anon-missing (both overloads).
grant execute on function public.record_auto_bug(text, text, text, text, text, text, jsonb, text, text, text, text, text)          to anon;
grant execute on function public.record_auto_bug(text, text, text, text, text, text, jsonb, text, text, text, text, text, integer) to anon;
