-- Migration: expense_envelope_sweep_cron
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601215524).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 5 Step 3)
--
-- Schedules the daily envelope sweep. Applied LAST (after the backfill filed Maverick's historical
-- orphans to History and after the deep_link_type correction) so the first run is clean and cannot
-- blast Maverick's approvers. Pre-flight verified: the only open envelope is Canpro's May envelope,
-- not due until 2026-06-07. 15:15 UTC daily, mirroring the house email-cron window. pg_cron is free
-- (no per-invocation cost).

select cron.schedule('expense_envelope_sweep_daily', '15 15 * * *', 'select public.expense_envelope_sweep();');
