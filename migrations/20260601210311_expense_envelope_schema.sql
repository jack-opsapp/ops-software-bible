-- Migration: expense_envelope_schema
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601210311).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Spec: ops-ios/docs/superpowers/specs/2026-06-01-expense-auto-batching-design.md
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 1)
--
-- Adds the per-org grace-days setting and widens the race-safety unique index so the
-- new 'open' (filling) envelope phase is also one-active-envelope-per-scope.

alter table public.expense_settings
  add column if not exists auto_submit_grace_days integer not null default 7;

-- Widen the race-safety index so the new 'open' (filling) phase is also one-per-scope.
drop index if exists public.expense_batches_open_unique;
create unique index expense_batches_open_unique
  on public.expense_batches (company_id, submitted_by, period_start, period_end, scope_project_id)
  nulls not distinct
  where status in ('open','pending_review') and amendment_number = 0;
