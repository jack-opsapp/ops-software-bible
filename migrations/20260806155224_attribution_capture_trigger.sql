create or replace function public.seed_trial_attribution_for_company()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  begin
    insert into public.trial_attributions (company_id, trial_started_at, attributed_channel)
    values (
      new.id,
      coalesce(new.trial_start_date, new.created_at, now()),
      'unknown'
    )
    on conflict (company_id) do nothing;
  exception when others then
    raise warning 'seed_trial_attribution_for_company failed for company %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists companies_seed_trial_attribution on public.companies;
create trigger companies_seed_trial_attribution
  after insert on public.companies
  for each row execute function public.seed_trial_attribution_for_company();

insert into public.trial_attributions (company_id, trial_started_at, attributed_channel)
select c.id,
       coalesce(c.trial_start_date, c.created_at, now()),
       'unknown'
from public.companies c
where c.deleted_at is null
on conflict (company_id) do nothing;

update public.trial_attributions ta
   set first_paid_at = f.first_paid,
       updated_at    = now()
from (
  select company_id, min(occurred_at) as first_paid
  from public.billing_events
  where event_type = 'invoice.paid' and company_id is not null
  group by company_id
) f
where ta.company_id = f.company_id
  and ta.first_paid_at is null;
