-- SPEC Phase 1 — Migration 2/8: OPS Operations internal company seed
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md § OPS Operations internal company
-- Constant UUID exported to application code as OPS_OPERATIONS_COMPANY_ID.
-- companies.name is NOT NULL; defaults handle timezone/locale/currency_code/etc.

insert into public.companies (id, name, created_at)
values (
  '00000000-0000-0000-0000-00000000000a',
  'OPS Operations',
  now()
)
on conflict (id) do nothing;
