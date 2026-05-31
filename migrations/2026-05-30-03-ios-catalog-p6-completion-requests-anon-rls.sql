-- 2026-05-30-03-ios-catalog-p6-completion-requests-anon-rls.sql
--
-- BLOCKER FIX (P6 task completion). public.task_material_consumption_requests has RLS
-- enabled, but all three policies were scoped `to authenticated`, while the app executes
-- as the Postgres `anon` role (identity rides in the JWT). pg_has_role('anon',
-- 'authenticated','USAGE') is false, so anon had ZERO applicable permissive policies
-- -> RLS default-deny (42501). public.complete_project_task flips
-- project_tasks.status='completed' and THEN private.consume_task_materials_for_completed_task
-- INSERTs into this table, so the whole completion transaction rolled back for every
-- user, in EVERY inventory mode (the off-mode early-return is downstream of the INSERT).
--
-- Every peer P6 write table (project_material_demands, task_material_allocations,
-- project_material_snapshots, project_material_snapshot_items, accept_estimate_to_job_requests)
-- already uses `to public`. This widens the three policies to match. The company scope
-- and the permission check are UNCHANGED (still enforced by each policy's USING/WITH CHECK
-- predicate: private.current_user_can_complete_task_material_consumption(company_id, task_id)
-- for insert/update, company_id = private.get_user_company_id() for select), so this grants
-- no access beyond what the peer tables already allow. Additive / idempotent.

alter policy task_material_consumption_requests_insert_rpc
  on public.task_material_consumption_requests to public;

alter policy task_material_consumption_requests_select_company
  on public.task_material_consumption_requests to public;

alter policy task_material_consumption_requests_update_rpc
  on public.task_material_consumption_requests to public;
