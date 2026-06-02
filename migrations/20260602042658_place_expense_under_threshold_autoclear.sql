-- Migration: place_expense_under_threshold_autoclear  (supersedes 20260601210846)
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-02 via Supabase MCP apply_migration (version 20260602042658).
-- Part of: Expense Auto-Batching — Phase 2 · Workstream A (server).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-2-workstream-a-server.md (A3)
--
-- Adds server-side under-threshold auto-clear: on placement, if amount < expense_settings.auto_approve_threshold,
-- the line still LANDS in its envelope (books stay complete) but is set 'approved' on the spot. This replaces
-- the old iOS client behavior of bypassing the batch entirely (draft->approved, no envelope). Preserves the
-- `order by id` allocation fix. Setting status fires trg_place_expense again but it no-ops (batch_id now set).
-- Validated: $10 under a $25 threshold -> placed + approved; $100 -> placed + still submitted.

create or replace function public.place_expense(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_exp     public.expenses;
  v_freq    text;
  v_ps      date; v_pe date;
  v_scope   uuid;
  v_batch   public.expense_batches;
  v_home_approved boolean;
  v_threshold numeric;
begin
  select * into v_exp from public.expenses where id = p_expense_id;
  if v_exp.id is null or v_exp.deleted_at is not null then return; end if;
  if v_exp.status = 'draft' or v_exp.batch_id is not null then return; end if;

  select coalesce(es.review_frequency,'monthly') into v_freq
  from public.expense_settings es where es.company_id = v_exp.company_id;
  v_freq := coalesce(v_freq,'monthly');

  select period_start, period_end into v_ps, v_pe
  from public.expense_envelope_period(v_exp.expense_date, v_freq);

  if v_freq = 'per_job' then
    select project_id into v_scope
    from public.expense_project_allocations
    where expense_id = v_exp.id order by id limit 1;   -- no created_at column on this table
  else
    v_scope := null;
  end if;

  select exists(
    select 1 from public.expense_batches b
    where b.company_id = v_exp.company_id and b.submitted_by = v_exp.submitted_by
      and b.amendment_number = 0 and b.status = 'approved'
      and coalesce(b.period_start,'1970-01-01'::date) = v_ps
      and coalesce(b.period_end,'1970-01-01'::date)   = v_pe
      and coalesce(b.scope_project_id,'00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(v_scope,'00000000-0000-0000-0000-000000000000'::uuid)
  ) into v_home_approved;

  if v_home_approved then
    select period_start, period_end into v_ps, v_pe
    from public.expense_envelope_period(current_date, v_freq);
  end if;

  v_batch := public.get_or_create_open_batch(
    v_exp.company_id, v_exp.submitted_by, v_ps, v_pe, v_scope);

  update public.expenses set batch_id = v_batch.id, updated_at = now()
  where id = v_exp.id;

  perform public.recalculate_expense_batch_total(v_batch.id);

  -- Under-threshold auto-clear: keep it in the envelope (books stay complete) but clear the line.
  select auto_approve_threshold into v_threshold
  from public.expense_settings es where es.company_id = v_exp.company_id;
  if coalesce(v_threshold, 0) > 0 and v_exp.amount is not null and v_exp.amount < v_threshold then
    update public.expenses set status = 'approved', updated_at = now()
    where id = v_exp.id and status <> 'approved';
  end if;
end;
$$;

revoke execute on function public.place_expense(uuid) from public, anon, authenticated;
grant  execute on function public.place_expense(uuid) to service_role;
