-- Harden enforce_expense_edit_authority: exempt trusted backend / cron /
-- SECURITY DEFINER-pipeline contexts, which run without a PostgREST JWT.
-- Anon API requests can't reach this trigger (RLS company_isolation requires a
-- resolved user first), so an absent request.jwt.claims reliably means a
-- trusted backend context (pg_cron sweep, admin SQL, data migration).
create or replace function private.enforce_expense_edit_authority()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_is_admin boolean;
begin
  -- Trusted backend context (no API JWT) -> skip; only authenticated app
  -- requests are subject to the uploader-only rule.
  if coalesce(current_setting('request.jwt.claims', true), '') = '' then
    return new;
  end if;

  v_uid := private.get_current_user_id();
  v_is_admin := private.current_user_is_admin();

  -- Content edits -> submitter only.
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
