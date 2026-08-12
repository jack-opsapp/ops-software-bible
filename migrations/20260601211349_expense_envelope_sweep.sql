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
    -- users_with_permission returns SETOF uuid (no 'user_id' column) -> select * from it.
    for v_uid in select * from public.users_with_permission(v_batch.company_id, 'expenses.approve')
    loop
      insert into public.notifications(
        user_id, company_id, type, title, body, batch_id, deep_link_type, action_url, action_label)
      values (
        v_uid::text, v_batch.company_id::text, 'expense_submitted',
        'Expenses ready for review',
        v_batch.batch_number || ' — ' || to_char(v_batch.period_start,'Mon YYYY')
          || ' (' || to_char(v_batch.total_amount,'FM999G999G990D00') || ')',
        v_batch.id::text, 'invoice_detail',
        '/expenses?batch=' || v_batch.id, 'REVIEW');
    end loop;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

revoke execute on function public.expense_envelope_sweep() from public, anon, authenticated;
grant  execute on function public.expense_envelope_sweep() to service_role;
