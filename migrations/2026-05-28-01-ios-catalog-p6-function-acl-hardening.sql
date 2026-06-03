-- Phase 6 post-apply function ACL hardening.
-- Forward-only correction for public RPC and trigger surfaces.
-- Does not change acceptance behavior, material demand logic, or stock deduction paths.

revoke execute on function public.set_company_inventory_mode(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_company_inventory_mode(uuid, text)
  to authenticated;

revoke execute on function public.accept_estimate_to_job(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_estimate_to_job(uuid, text)
  to authenticated;

revoke execute on function public.fn_set_updated_at()
  from public, anon, authenticated, service_role;

revoke execute on function public.company_inventory_settings_write_guard()
  from public, anon, authenticated, service_role;

revoke execute on function public.project_material_workflow_write_guard()
  from public, anon, authenticated, service_role;

revoke execute on function public.project_material_demands_company_guard()
  from public, anon, authenticated, service_role;

revoke execute on function public.project_material_snapshots_company_guard()
  from public, anon, authenticated, service_role;

revoke execute on function public.project_material_snapshot_items_company_guard()
  from public, anon, authenticated, service_role;

revoke execute on function public.task_material_allocations_company_guard()
  from public, anon, authenticated, service_role;

revoke execute on function public.accept_estimate_to_job_requests_write_guard()
  from public, anon, authenticated, service_role;
