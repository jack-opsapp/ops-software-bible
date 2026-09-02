-- Companion to ledger 20260902160624 (soft_delete_project_task_rpc).
--
-- Supabase's default privileges on `public` grant EXECUTE to service_role on
-- every newly created function, so the two soft-delete wrappers landed with a
-- service_role grant the migration never asked for. `revoke ... from public`
-- does not remove it — it is an explicit grant, not the PUBLIC pseudo-role.
--
-- Both wrappers already refuse any caller whose auth.role() is not anon or
-- authenticated, so this changes no behavior; it aligns the ACL with the
-- narrow-RPC doctrine (07_SPECIALIZED_FEATURES.md §14) and with the closest
-- sibling, public.update_task_with_event, whose ACL is postgres + anon +
-- authenticated only. The service lane needs no grant here: service_role
-- bypasses RLS and can retire a task directly.

revoke execute on function public.soft_delete_project_task(uuid) from service_role;
revoke execute on function public.soft_delete_task_recurrence(uuid) from service_role;
