-- Uploader-only edit + uploader-or-admin delete for expenses (2026-06-09).
-- Content edits are restricted to the submitter; soft-delete (setting
-- deleted_at) to the submitter or a company admin. Approval / flag / status
-- transitions and the server placement pipeline (place_expense, sweep,
-- approval RPCs) never touch content columns or set deleted_at on another
-- user's behalf, so this BEFORE UPDATE trigger is purely additive over the
-- existing role_scope_update RLS policy: it only narrows who may change
-- content (submitter) and who may delete (submitter or admin).

create or replace function private.enforce_expense_edit_authority()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := private.get_current_user_id();
  v_is_admin boolean := private.current_user_is_admin();
begin
  -- Content edits -> submitter only (owners/office review via approve/reject,
  -- they do not edit a teammate's line).
  if ( new.merchant_name         is distinct from old.merchant_name
    or new.description           is distinct from old.description
    or new.amount                is distinct from old.amount
    or new.tax_amount            is distinct from old.tax_amount
    or new.currency              is distinct from old.currency
    or new.expense_date          is distinct from old.expense_date
    or new.payment_method        is distinct from old.payment_method
    or new.category_id           is distinct from old.category_id
    or new.receipt_image_url     is distinct from old.receipt_image_url
    or new.receipt_thumbnail_url is distinct from old.receipt_thumbnail_url
    or new.ocr_raw_data          is distinct from old.ocr_raw_data
    or new.ocr_confidence        is distinct from old.ocr_confidence )
  then
    if v_uid is null or v_uid <> old.submitted_by then
      raise exception 'Only the expense submitter may edit its details'
        using errcode = '42501';
    end if;
  end if;

  -- Soft delete (setting deleted_at) -> submitter or company admin.
  if new.deleted_at is distinct from old.deleted_at and new.deleted_at is not null then
    if not (v_is_admin or (v_uid is not null and v_uid = old.submitted_by)) then
      raise exception 'Only the submitter or a company admin may delete this expense'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_expense_edit_authority on public.expenses;
create trigger trg_enforce_expense_edit_authority
  before update on public.expenses
  for each row
  execute function private.enforce_expense_edit_authority();
