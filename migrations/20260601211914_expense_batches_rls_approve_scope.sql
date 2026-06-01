-- Migration: expense_batches_rls_approve_scope
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601211914).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 6)
--
-- Closes the self-approve gap. expense_batches previously had only company_isolation
-- (PERMISSIVE, FOR ALL) — any company member could flip their own batch to 'approved' via a
-- direct write. This RESTRICTIVE UPDATE policy AND's with company_isolation and only lets a
-- batch move into 'approved'/'auto_approved' when the actor holds expenses.approve.
-- Server functions (place_expense, expense_envelope_sweep, get_or_create_open_batch) run as
-- SECURITY DEFINER and the backfill runs as service_role — both bypass RLS; this guards only
-- direct client writes. Helpers verified present on prod: private.get_user_company_id(),
-- private.get_current_user_id(), public.has_permission(uuid,text,text).

create policy expense_batches_approve_scope
on public.expense_batches
as restrictive
for update
to public
using ( company_id = (select private.get_user_company_id()) )
with check (
  company_id = (select private.get_user_company_id())
  and (
    status not in ('approved','auto_approved')
    or public.has_permission((select private.get_current_user_id()), 'expenses.approve', 'all')
  )
);
