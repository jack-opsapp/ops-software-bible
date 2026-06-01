-- Migration: expense_envelope_period_fn
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601210428).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 2)
--
-- Server-side period math: SQL port of ops-ios/OPS/DataModels/Helpers/ExpenseBatchPeriod.swift.
-- Returns the (period_start, period_end) window for an expense given its date + the
-- company's review_frequency. Postgres week starts Monday (ISO), matching the Swift
-- Calendar(firstWeekday=2). Unknown / null frequency falls back to monthly.

create or replace function public.expense_envelope_period(p_expense_date date, p_review_frequency text)
returns table(period_start date, period_end date)
language sql
immutable
set search_path to 'public','pg_temp'
as $$
  select
    case coalesce(p_review_frequency,'monthly')
      when 'per_job'   then p_expense_date
      when 'weekly'    then date_trunc('week', p_expense_date)::date            -- Postgres week starts Monday
      when 'biweekly'  then case when extract(day from p_expense_date) <= 14
                                 then date_trunc('month', p_expense_date)::date
                                 else (date_trunc('month', p_expense_date) + interval '14 days')::date end
      when 'quarterly' then date_trunc('quarter', p_expense_date)::date
      else date_trunc('month', p_expense_date)::date                            -- monthly + unknown
    end as period_start,
    case coalesce(p_review_frequency,'monthly')
      when 'per_job'   then p_expense_date
      when 'weekly'    then (date_trunc('week', p_expense_date) + interval '6 days')::date
      when 'biweekly'  then case when extract(day from p_expense_date) <= 14
                                 then (date_trunc('month', p_expense_date) + interval '13 days')::date
                                 else (date_trunc('month', p_expense_date) + interval '1 month - 1 day')::date end
      when 'quarterly' then (date_trunc('quarter', p_expense_date) + interval '3 months - 1 day')::date
      else (date_trunc('month', p_expense_date) + interval '1 month - 1 day')::date
    end as period_end;
$$;
