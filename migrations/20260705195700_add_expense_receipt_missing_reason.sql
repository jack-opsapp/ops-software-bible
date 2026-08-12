-- Additive, non-breaking: two nullable columns to record why an expense has no
-- receipt photo when the company requires one (require_receipt_photo = true).
-- Shipped iOS builds neither read nor write these; the CHECK only constrains
-- non-null values, written solely by the updated iOS build (stable 4-code enum).
alter table public.expenses
  add column if not exists receipt_missing_reason text,
  add column if not exists receipt_missing_note text;

comment on column public.expenses.receipt_missing_reason is
  'Why this expense has no receipt photo (escape hatch when require_receipt_photo=true). One of lost|cash|digital|other, else NULL.';
comment on column public.expenses.receipt_missing_note is
  'Optional free-text note accompanying receipt_missing_reason.';

alter table public.expenses
  add constraint expenses_receipt_missing_reason_check
  check (
    receipt_missing_reason is null
    or receipt_missing_reason in ('lost','cash','digital','other')
  );
