-- Migration: lock_tg_place_expense_to_trigger_only
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601215540).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain) — post-advisor hardening.
--
-- Closes a security advisor WARN (anon/authenticated_security_definer_function_executable): the
-- Task 4 migration revoked place_expense but not its trigger fn tg_place_expense(), leaving it
-- directly callable by anon/authenticated. REVOKE direct EXECUTE — the trg_place_expense trigger
-- still fires normally (trigger invocation does not check EXECUTE privileges). No grant to
-- service_role is needed; the trigger runs as the function owner. Matches the house lockdown
-- pattern (see 20260601164310_lock_server_only_functions_to_service_role.sql).

revoke execute on function public.tg_place_expense() from public, anon, authenticated;
