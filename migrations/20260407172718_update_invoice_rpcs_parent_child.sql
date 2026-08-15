CREATE OR REPLACE FUNCTION public.convert_estimate_to_invoice(p_estimate_id uuid, p_due_date date DEFAULT (CURRENT_DATE + 30))
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_estimate estimates%ROWTYPE;
  v_invoice_id uuid;
  v_invoice_number text;
  v_old_id uuid;
  v_new_id uuid;
BEGIN
  SELECT * INTO v_estimate FROM estimates WHERE id = p_estimate_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Estimate not found'; END IF;
  IF v_estimate.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved estimates can become invoices (current: %)', v_estimate.status;
  END IF;

  v_invoice_number := get_next_document_number(v_estimate.company_id, 'invoice');

  INSERT INTO invoices (
    company_id, client_id, estimate_id, opportunity_id,
    invoice_number, subtotal, discount_type, discount_value, discount_amount,
    tax_rate, tax_amount, total, balance_due,
    due_date, terms, deposit_applied, created_by
  ) VALUES (
    v_estimate.company_id, v_estimate.client_id, v_estimate.id, v_estimate.opportunity_id,
    v_invoice_number, v_estimate.subtotal, v_estimate.discount_type, v_estimate.discount_value,
    v_estimate.discount_amount, v_estimate.tax_rate, v_estimate.tax_amount, v_estimate.total,
    v_estimate.total - COALESCE(v_estimate.deposit_amount, 0),
    p_due_date, v_estimate.terms, COALESCE(v_estimate.deposit_amount, 0), v_estimate.created_by
  ) RETURNING id INTO v_invoice_id;

  -- Pass 1: Copy parent/standalone line items (no parent_line_item_id)
  -- Use a temp table to track old→new ID mapping
  CREATE TEMP TABLE _parent_map (old_id uuid, new_id uuid) ON COMMIT DROP;

  INSERT INTO line_items (
    company_id, invoice_id, product_id, name, description,
    quantity, unit, unit_price, unit_cost, discount_percent,
    is_taxable, tax_rate_id, sort_order, category, type, task_type_id,
    parent_line_item_id
  )
  SELECT
    company_id, v_invoice_id, product_id, name, description,
    quantity, unit, unit_price, unit_cost, discount_percent,
    is_taxable, tax_rate_id, sort_order, category, type, task_type_id,
    NULL
  FROM line_items
  WHERE estimate_id = p_estimate_id
    AND parent_line_item_id IS NULL
    AND (is_optional = false OR is_selected = true);

  -- Build mapping: match by sort_order + name (unique within an estimate)
  INSERT INTO _parent_map (old_id, new_id)
  SELECT est.id, inv.id
  FROM line_items est
  JOIN line_items inv ON inv.invoice_id = v_invoice_id
    AND inv.sort_order = est.sort_order
    AND inv.name = est.name
  WHERE est.estimate_id = p_estimate_id
    AND est.parent_line_item_id IS NULL
    AND (est.is_optional = false OR est.is_selected = true);

  -- Pass 2: Copy child line items with remapped parent IDs
  INSERT INTO line_items (
    company_id, invoice_id, product_id, name, description,
    quantity, unit, unit_price, unit_cost, discount_percent,
    is_taxable, tax_rate_id, sort_order, category, type, task_type_id,
    parent_line_item_id
  )
  SELECT
    c.company_id, v_invoice_id, c.product_id, c.name, c.description,
    c.quantity, c.unit, c.unit_price, c.unit_cost, c.discount_percent,
    c.is_taxable, c.tax_rate_id, c.sort_order, c.category, c.type, c.task_type_id,
    pm.new_id
  FROM line_items c
  JOIN _parent_map pm ON pm.old_id = c.parent_line_item_id
  WHERE c.estimate_id = p_estimate_id;

  UPDATE estimates SET status = 'converted', updated_at = now() WHERE id = p_estimate_id;

  INSERT INTO activities (company_id, opportunity_id, client_id, estimate_id, invoice_id, type, subject, created_by)
  VALUES (v_estimate.company_id, v_estimate.opportunity_id, v_estimate.client_id,
          p_estimate_id, v_invoice_id, 'invoice_sent',
          'Invoice ' || v_invoice_number || ' created from estimate', v_estimate.created_by);

  RETURN v_invoice_id;
END; $function$;
