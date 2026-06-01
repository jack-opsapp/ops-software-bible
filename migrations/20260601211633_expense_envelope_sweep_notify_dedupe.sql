-- Migration: expense_envelope_sweep_notify_dedupe  (the daily envelope sweep function — final)
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-01 via Supabase MCP apply_migration (version 20260601211633).
-- Part of: Expense Auto-Batching — Phase 1 (Server Brain).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-1-server.md  (Task 5)
--
-- The daily sweep: (1) safety net adopts any non-draft unbatched expense (ends the stranding
-- bug for any client/version); (2) auto-sends every 'open' envelope past period_end + grace,
-- sweeping in that person's completed (amount > 0) drafts, flipping open -> pending_review
-- (the idempotency guard), and notifying every expenses.approve holder once per envelope.
--
-- NOTES (deviations from plan, verified against prod schema during a rolled-back real-data dry-run):
--   1. users_with_permission returns SETOF uuid (no 'user_id' column) -> `select * from` it.
--   2. The notification insert carries a per-envelope dedupe_key ('expense_batch_review:'||batch_id)
--      and ON CONFLICT DO NOTHING. Without this, auto-sending 2+ envelopes to the same approver in
--      one run collided on the partial unique index notifications_unread_title_dedup_without_key
--      (user_id, company_id, type, title WHERE dedupe_key IS NULL) and aborted the entire sweep.
--      A non-null dedupe_key routes dedup to notifications_open_dedupe_key
--      (user_id, company_id, type, dedupe_key) so each envelope is a distinct notification.
--   3. "Blank draft" = amount 0 (expenses.amount is NOT NULL); the amount > 0 filter holds them.
--   4. Supersedes an initial same-session cut (migration 20260601211349) that lacked the dedupe_key.
--
-- The cron schedule is a separate migration (expense_envelope_sweep_cron), applied only AFTER the
-- one-time backfill filed Maverick's historical orphans to History — so the first cron run could
-- not blast Maverick's approvers with back-dated review notifications.

create or replace function public.expense_envelope_sweep()
returns integer
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_sent int := 0;
  v_batch record;
  v_uid uuid;
  v_draft record;
begin
  -- (1) SAFETY NET: adopt any non-draft, unbatched expense (orphans from old clients / failed calls).
  for v_draft in
    select id from public.expenses
    where deleted_at is null and status <> 'draft' and batch_id is null
    for update skip locked
  loop
    perform public.place_expense(v_draft.id);
  end loop;

  -- (2) AUTO-SEND: every 'open' envelope whose period + grace has elapsed.
  for v_batch in
    select b.* from public.expense_batches b
    where b.status = 'open' and b.amendment_number = 0
      and b.period_end + (
        coalesce((select auto_submit_grace_days from public.expense_settings s
                  where s.company_id = b.company_id), 7) * interval '1 day'
      ) <= now()
    for update of b skip locked
  loop
    -- sweep this person's completed drafts (amount present) for the period into the envelope
    for v_draft in
      select id from public.expenses e
      where e.company_id = v_batch.company_id and e.submitted_by = v_batch.submitted_by
        and e.status = 'draft' and e.deleted_at is null and e.amount is not null and e.amount > 0
        and e.expense_date between v_batch.period_start and v_batch.period_end
      for update skip locked
    loop
      update public.expenses set status='submitted', batch_id=v_batch.id, updated_at=now() where id=v_draft.id;
    end loop;

    perform public.recalculate_expense_batch_total(v_batch.id);

    -- flip open -> pending_review (this transition is the idempotency guard: never re-picked)
    update public.expense_batches set status='pending_review' where id = v_batch.id;

    -- notify every approver (granular permission, never role).
    for v_uid in select * from public.users_with_permission(v_batch.company_id, 'expenses.approve')
    loop
      insert into public.notifications(
        user_id, company_id, type, title, body, batch_id, deep_link_type, action_url, action_label, dedupe_key)
      values (
        v_uid::text, v_batch.company_id::text, 'expense_submitted',
        'Expenses ready for review',
        v_batch.batch_number || ' — ' || to_char(v_batch.period_start,'Mon YYYY')
          || ' (' || to_char(v_batch.total_amount,'FM999G999G990D00') || ')',
        v_batch.id::text, 'invoice_detail',
        '/expenses?batch=' || v_batch.id, 'REVIEW',
        'expense_batch_review:' || v_batch.id)
      on conflict do nothing;
    end loop;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

revoke execute on function public.expense_envelope_sweep() from public, anon, authenticated;
grant  execute on function public.expense_envelope_sweep() to service_role;
