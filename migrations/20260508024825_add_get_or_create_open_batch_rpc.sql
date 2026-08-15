-- Always-bundle architecture support.
-- Adds a partial unique index to prevent duplicate open batches under
-- concurrent submission, plus a get-or-create RPC that returns the
-- caller's open batch for a (period_start, period_end) window or
-- creates one atomically.
--
-- per_job semantics live in the caller: pass p_force_new=true so a new
-- batch is created per submission instead of reusing.

-- Partial unique index: at most one open (pending_review, non-amendment)
-- batch per (company, submitter, period). Existing wild data verified
-- duplicate-free before adding.
create unique index if not exists expense_batches_open_unique
  on public.expense_batches (company_id, submitted_by, period_start, period_end)
  where status = 'pending_review' and amendment_number = 0;

create or replace function public.get_or_create_open_batch(
  p_company_id uuid,
  p_submitted_by uuid,
  p_period_start date,
  p_period_end date,
  p_force_new boolean default false
) returns public.expense_batches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_batch public.expense_batches;
begin
  if p_company_id is null or p_submitted_by is null then
    raise exception 'get_or_create_open_batch: company_id and submitted_by are required';
  end if;

  if not p_force_new then
    select * into v_batch
    from public.expense_batches
    where company_id = p_company_id
      and submitted_by = p_submitted_by
      and status = 'pending_review'
      and amendment_number = 0
      and coalesce(period_start, '1970-01-01'::date) = coalesce(p_period_start, '1970-01-01'::date)
      and coalesce(period_end,   '1970-01-01'::date) = coalesce(p_period_end,   '1970-01-01'::date)
    order by created_at desc
    limit 1;

    if v_batch.id is not null then
      return v_batch;
    end if;
  end if;

  insert into public.expense_batches (
    company_id,
    batch_number,
    period_start,
    period_end,
    status,
    submitted_by,
    total_amount,
    amendment_number
  ) values (
    p_company_id,
    public.get_next_expense_batch_number(p_company_id),
    p_period_start,
    p_period_end,
    'pending_review',
    p_submitted_by,
    0,
    0
  )
  returning * into v_batch;

  return v_batch;
end;
$$;

comment on function public.get_or_create_open_batch(uuid, uuid, date, date, boolean) is
  'Returns the user''s currently-open (status=pending_review, non-amendment) '
  'expense_batch for the given period, or creates one atomically. Used for '
  'always-bundle-on-submit. Pass p_force_new=true to skip the lookup '
  '(per_job review_frequency creates a new batch per expense).';

grant execute on function public.get_or_create_open_batch(uuid, uuid, date, date, boolean) to authenticated, service_role;

-- Atomic helper: recompute a batch's total_amount from its non-deleted
-- expenses. Used after attaching new expenses on submission so the
-- threshold check sees the right total.
create or replace function public.recalculate_expense_batch_total(p_batch_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_total numeric;
begin
  select coalesce(sum(amount), 0)
    into v_total
    from public.expenses
   where batch_id = p_batch_id
     and deleted_at is null;

  update public.expense_batches
     set total_amount = v_total
   where id = p_batch_id;

  return v_total;
end;
$$;

grant execute on function public.recalculate_expense_batch_total(uuid) to authenticated, service_role;
