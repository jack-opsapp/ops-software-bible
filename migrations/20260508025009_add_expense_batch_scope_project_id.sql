-- per_job review_frequency: batches are project-scoped, not period-scoped.
-- Adding scope_project_id (nullable; NULL for period-mode batches) lets us
-- key open batches on (company, user, period, project) so per_job companies
-- accumulate multiple expenses for the same project into the same batch
-- while still enforcing one open batch per scope.

alter table public.expense_batches
  add column if not exists scope_project_id uuid;

-- Replace the unique index with one that includes the project scope.
-- NULLS NOT DISTINCT (Postgres 15+) so two NULL scope_project_ids still
-- conflict when (company, user, period) match — period-mode behavior.
drop index if exists public.expense_batches_open_unique;

create unique index expense_batches_open_unique
  on public.expense_batches (
    company_id, submitted_by, period_start, period_end, scope_project_id
  )
  nulls not distinct
  where status = 'pending_review' and amendment_number = 0;

-- Updated function signature: accept p_scope_project_id and drop the
-- now-redundant p_force_new parameter (per_job calls pass a non-null
-- project; period modes pass null).
drop function if exists public.get_or_create_open_batch(uuid, uuid, date, date, boolean);

create or replace function public.get_or_create_open_batch(
  p_company_id uuid,
  p_submitted_by uuid,
  p_period_start date,
  p_period_end date,
  p_scope_project_id uuid default null
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

  -- Find existing open batch for the scope.
  select * into v_batch
  from public.expense_batches
  where company_id = p_company_id
    and submitted_by = p_submitted_by
    and status = 'pending_review'
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

  -- Create new. Race-safety: if a concurrent caller wins the unique index,
  -- catch unique_violation and re-select.
  begin
    insert into public.expense_batches (
      company_id,
      batch_number,
      period_start,
      period_end,
      status,
      submitted_by,
      total_amount,
      amendment_number,
      scope_project_id
    ) values (
      p_company_id,
      public.get_next_expense_batch_number(p_company_id),
      p_period_start,
      p_period_end,
      'pending_review',
      p_submitted_by,
      0,
      0,
      p_scope_project_id
    )
    returning * into v_batch;
  exception when unique_violation then
    select * into v_batch
    from public.expense_batches
    where company_id = p_company_id
      and submitted_by = p_submitted_by
      and status = 'pending_review'
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
$$;

comment on function public.get_or_create_open_batch(uuid, uuid, date, date, uuid) is
  'Returns the user''s open (pending_review, non-amendment) expense_batch '
  'matching the scope, or creates one atomically. For per_job '
  'review_frequency, pass the expense''s project as p_scope_project_id so '
  'multiple expenses for the same project accumulate into the same batch. '
  'Period modes pass NULL.';

grant execute on function public.get_or_create_open_batch(uuid, uuid, date, date, uuid) to authenticated, service_role;
