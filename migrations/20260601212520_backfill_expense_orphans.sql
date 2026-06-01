-- Migration: backfill_expense_orphans
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601212520).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 7)
--
-- One-time backfill: place every pre-existing non-draft, unbatched (orphaned) expense into its
-- correct per-person/per-period envelope via the authoritative placement function. Ended the live
-- stranding backlog (53 orphans: Canpro 2 + Maverick 51). Verified after: 0 orphans remain globally.
--
-- Operator decision (2026-06-01): MAVERICK PROJECTS LTD's 51 historical orphans (Oct 2025–Apr 2026,
-- weekly cadence) were filed to History (envelope status 'auto_approved', lines 'approved') so the
-- first daily sweep could not blast Maverick's 2 approvers with back-dated review notifications.
-- Canpro's 2 (Charlie Gatenby's May 2026 receipts) were placed normally into a fresh open May
-- envelope (EXP-BATCH-0003) that auto-sends on June 7 (monthly + 7-day grace).
do $$
declare
  r record;
  v_mav uuid := 'ddee107c-33cd-483e-8278-0f8d8a180181';  -- MAVERICK PROJECTS LTD
  v_mav_orphans uuid[];
begin
  -- Capture Maverick's orphan ids BEFORE placement (file exactly these envelopes to History).
  select array_agg(id) into v_mav_orphans
  from public.expenses
  where company_id = v_mav and deleted_at is null and status <> 'draft' and batch_id is null;

  -- Place EVERY orphan (all companies) into its per-person/per-period envelope by date.
  for r in
    select id from public.expenses
    where deleted_at is null and status <> 'draft' and batch_id is null
    order by expense_date
  loop
    perform public.place_expense(r.id);
  end loop;

  -- Maverick: file the freshly-created (open) envelopes to History; pre-existing batches untouched.
  if v_mav_orphans is not null then
    update public.expense_batches b
       set status = 'auto_approved'
     where b.company_id = v_mav
       and b.status = 'open'
       and b.id in (select distinct e.batch_id from public.expenses e where e.id = any(v_mav_orphans));

    update public.expenses e
       set status = 'approved', updated_at = now()
      from public.expense_batches b
     where e.batch_id = b.id
       and b.company_id = v_mav
       and b.status = 'auto_approved'
       and e.id = any(v_mav_orphans);
  end if;
end $$;
