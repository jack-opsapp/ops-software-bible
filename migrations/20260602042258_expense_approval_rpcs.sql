-- Migration: expense_approval_rpcs
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-02 via Supabase MCP apply_migration (version 20260602042258).
-- Part of: Expense Auto-Batching — Phase 2 · Workstream A (server).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-2-workstream-a-server.md (A1)
--
-- Atomic, permission-checked approval RPCs. Both are SECURITY DEFINER and internally enforce
-- expenses.approve via has_permission(private.get_current_user_id(), ...). This lets OPS-Web stop
-- doing a non-transactional two-write approve (batch UPDATE gated by expenses.approve + line UPDATE
-- gated by expenses.edit), which risked partial failure + a permission mismatch. reviewed_by is uuid
-- (verified) so v_uid is assigned directly; notifications.* are text so submitted_by/company_id/id are ::text.
-- Validated: guard rejects an unauthorized caller; write logic approves batch + non-rejected lines.

create or replace function public.approve_expense_batch(p_batch_id uuid)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_uid uuid := private.get_current_user_id(); v_batch public.expense_batches;
begin
  if v_uid is null or not public.has_permission(v_uid,'expenses.approve','all') then
    raise exception 'approve_expense_batch: caller lacks expenses.approve';
  end if;
  select * into v_batch from public.expense_batches where id = p_batch_id;
  if v_batch.id is null then raise exception 'approve_expense_batch: batch % not found', p_batch_id; end if;
  update public.expenses set status='approved', updated_at=now()
   where batch_id = p_batch_id and deleted_at is null and status not in ('rejected','approved','reimbursed');
  update public.expense_batches set status='approved', reviewed_by=v_uid, reviewed_at=now() where id = p_batch_id;
  perform public.recalculate_expense_batch_total(p_batch_id);
end; $$;

create or replace function public.early_clear_expense_line(p_expense_id uuid)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_uid uuid := private.get_current_user_id(); v_exp public.expenses;
begin
  if v_uid is null or not public.has_permission(v_uid,'expenses.approve','all') then
    raise exception 'early_clear_expense_line: caller lacks expenses.approve';
  end if;
  select * into v_exp from public.expenses where id = p_expense_id;
  if v_exp.id is null then raise exception 'early_clear_expense_line: expense % not found', p_expense_id; end if;
  update public.expenses set status='approved', updated_at=now() where id = p_expense_id;
  if v_exp.batch_id is not null then perform public.recalculate_expense_batch_total(v_exp.batch_id); end if;
  insert into public.notifications(user_id, company_id, type, title, body, expense_id, deep_link_type, action_url, action_label, dedupe_key)
  values (v_exp.submitted_by::text, v_exp.company_id::text, 'expense_approved', 'Expense approved',
          coalesce(v_exp.merchant_name,'Expense') || ' (' || to_char(v_exp.amount,'FM999G999G990D00') || ') was cleared',
          v_exp.id::text, 'expense', '/accounting?tab=expenses', 'VIEW', 'expense_cleared:' || v_exp.id)
  on conflict do nothing;
end; $$;

grant execute on function public.approve_expense_batch(uuid)   to anon, authenticated, service_role;
grant execute on function public.early_clear_expense_line(uuid) to anon, authenticated, service_role;
