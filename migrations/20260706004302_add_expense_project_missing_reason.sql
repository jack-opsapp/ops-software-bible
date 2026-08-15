-- Additive, non-breaking: mirror of receipt_missing_* for the require_project_assignment
-- escape hatch. Nullable columns; CHECK only constrains non-null values written by the
-- updated iOS build. Shipped builds neither read nor write these.
alter table public.expenses
  add column if not exists project_missing_reason text,
  add column if not exists project_missing_note text;

comment on column public.expenses.project_missing_reason is
  'Why this expense has no project when require_project_assignment=true. One of overhead|general|other, else NULL.';
comment on column public.expenses.project_missing_note is
  'Optional free-text note accompanying project_missing_reason.';

alter table public.expenses
  add constraint expenses_project_missing_reason_check
  check (
    project_missing_reason is null
    or project_missing_reason in ('overhead','general','other')
  );
