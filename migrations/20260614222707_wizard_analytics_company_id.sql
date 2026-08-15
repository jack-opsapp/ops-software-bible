alter table public.wizard_analytics
  add column if not exists company_id uuid references public.companies(id) on delete set null;

create index if not exists wizard_analytics_company_id_idx
  on public.wizard_analytics (company_id);

comment on column public.wizard_analytics.company_id is
  'Company the wizard session belongs to. Nullable for legacy iOS rows.';
