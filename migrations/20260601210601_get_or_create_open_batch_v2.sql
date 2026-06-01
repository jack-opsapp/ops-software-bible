-- Migration: get_or_create_open_batch_v2
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601210601).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 3)
--
-- Extends the existing race-safe get-or-create so it now creates the envelope in the
-- 'open' (filling) phase and matches an existing not-yet-approved envelope ('open' OR
-- 'pending_review') — so a late item joins a not-yet-approved envelope even after it has
-- sent. Same signature/return as the original (3.0.3 clients keep calling it unchanged).

create or replace function public.get_or_create_open_batch(
  p_company_id uuid, p_submitted_by uuid, p_period_start date, p_period_end date,
  p_scope_project_id uuid default null::uuid)
returns expense_batches
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_batch public.expense_batches;
begin
  if p_company_id is null or p_submitted_by is null then
    raise exception 'get_or_create_open_batch: company_id and submitted_by are required';
  end if;

  -- Match a not-yet-approved envelope (filling OR already-sent) for the scope.
  select * into v_batch
  from public.expense_batches
  where company_id = p_company_id
    and submitted_by = p_submitted_by
    and status in ('open','pending_review')
    and amendment_number = 0
    and coalesce(period_start,     '1970-01-01'::date) = coalesce(p_period_start,     '1970-01-01'::date)
    and coalesce(period_end,       '1970-01-01'::date) = coalesce(p_period_end,       '1970-01-01'::date)
    and coalesce(scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid) =
        coalesce(p_scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid)
  order by created_at desc
  limit 1;

  if v_batch.id is not null then
    return v_batch;
  end if;

  begin
    insert into public.expense_batches (
      company_id, batch_number, period_start, period_end,
      status, submitted_by, total_amount, amendment_number, scope_project_id
    ) values (
      p_company_id, public.get_next_expense_batch_number(p_company_id),
      p_period_start, p_period_end, 'open', p_submitted_by, 0, 0, p_scope_project_id)
    returning * into v_batch;
  exception when unique_violation then
    select * into v_batch
    from public.expense_batches
    where company_id = p_company_id
      and submitted_by = p_submitted_by
      and status in ('open','pending_review')
      and amendment_number = 0
      and coalesce(period_start,     '1970-01-01'::date) = coalesce(p_period_start,     '1970-01-01'::date)
      and coalesce(period_end,       '1970-01-01'::date) = coalesce(p_period_end,       '1970-01-01'::date)
      and coalesce(scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid) =
          coalesce(p_scope_project_id, '00000000-0000-0000-0000-000000000000'::uuid)
    order by created_at desc
    limit 1;
  end;

  return v_batch;
end;
$function$;
