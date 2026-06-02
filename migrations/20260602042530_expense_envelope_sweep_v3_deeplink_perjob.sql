-- Migration: expense_envelope_sweep_v3_deeplink_perjob  (daily sweep — supersedes 20260601213757)
-- Applied to prod (ijeekuhbatykdomumfjx) 2026-06-02 via Supabase MCP apply_migration (version 20260602042530).
-- Part of: Expense Auto-Batching — Phase 2 · Workstream A (server).
-- Plan: ops-ios/docs/superpowers/plans/2026-06-01-expense-auto-batching-phase-2-workstream-a-server.md (A2)
--
-- Two changes vs 20260601213757:
--   1. Notification action_url -> '/accounting?tab=expenses&batch='||id. The prior '/expenses?batch='
--      404s on web (office UI is /accounting?tab=expenses; web rail routes purely on action_url).
--   2. per_job companies auto-send N days after the linked project's completed_at (join scope_project_id
--      -> projects.id), not on a calendar — a single-day per_job period would otherwise send grace days
--      after the expense date. An envelope whose project isn't complete stays 'open' (office can send manually).
-- Validated: monthly overdue sends with the routable action_url; per_job held while project incomplete,
-- sent once completed_at + grace has passed.

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
  -- (1) SAFETY NET: adopt any non-draft, unbatched expense.
  for v_draft in
    select id from public.expenses
    where deleted_at is null and status <> 'draft' and batch_id is null
    for update skip locked
  loop
    perform public.place_expense(v_draft.id);
  end loop;

  -- (2) AUTO-SEND: every 'open' envelope that is due. Calendar period+grace for normal cadences;
  -- project completion+grace for per_job.
  for v_batch in
    select b.* from public.expense_batches b
    where b.status = 'open' and b.amendment_number = 0
      and (
        case
          when coalesce((select s.review_frequency from public.expense_settings s where s.company_id = b.company_id),'monthly') = 'per_job'
            then (select p.completed_at from public.projects p where p.id = b.scope_project_id) is not null
                 and (select p.completed_at from public.projects p where p.id = b.scope_project_id)
                     + (coalesce((select auto_submit_grace_days from public.expense_settings s where s.company_id = b.company_id), 7) * interval '1 day') <= now()
          else b.period_end
                 + (coalesce((select auto_submit_grace_days from public.expense_settings s where s.company_id = b.company_id), 7) * interval '1 day') <= now()
        end
      )
    for update of b skip locked
  loop
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
    update public.expense_batches set status='pending_review' where id = v_batch.id;

    for v_uid in select * from public.users_with_permission(v_batch.company_id, 'expenses.approve')
    loop
      insert into public.notifications(
        user_id, company_id, type, title, body, batch_id, deep_link_type, action_url, action_label, dedupe_key)
      values (
        v_uid::text, v_batch.company_id::text, 'expense_submitted',
        'Expenses ready for review',
        v_batch.batch_number || ' — ' || to_char(v_batch.period_start,'Mon YYYY')
          || ' (' || to_char(v_batch.total_amount,'FM999G999G990D00') || ')',
        v_batch.id::text, 'expense',
        '/accounting?tab=expenses&batch=' || v_batch.id, 'REVIEW',
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
