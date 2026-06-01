-- Migration: place_expense_trigger
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601210846).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 4)
--
-- The no-strand guarantee: a DB trigger places every non-draft, unbatched expense into its
-- per-person/per-period envelope by the expense's *date*, regardless of which client wrote it.
-- Rolls forward into the current open period when the home period's envelope is already approved.
--
-- NOTE (deviation from plan, verified against prod schema): the per_job scope lookup orders by
-- `id`, not `created_at` — expense_project_allocations has no created_at column
-- (columns: id, expense_id, project_id, percentage, amount). The plan's `order by created_at`
-- would have thrown on every per_job placement.

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
    where expense_id = v_exp.id order by id limit 1;   -- FIX: no created_at column on this table
  else
    v_scope := null;
  end if;

  -- Home-period envelope already approved? Then roll forward to the current period.
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
end;
$$;

create or replace function public.tg_place_expense()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  if NEW.deleted_at is null and NEW.status <> 'draft' and NEW.batch_id is null then
    perform public.place_expense(NEW.id);
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_place_expense on public.expenses;
create trigger trg_place_expense
after insert or update of status, expense_date, batch_id on public.expenses
for each row execute function public.tg_place_expense();

-- Server-only: trigger fn + placement fn are never called by clients.
revoke execute on function public.place_expense(uuid) from public, anon, authenticated;
grant  execute on function public.place_expense(uuid) to service_role;
