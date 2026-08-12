
CREATE OR REPLACE FUNCTION create_progress_invoice(
  p_estimate_id uuid,
  p_line_item_selections jsonb  -- [{"line_item_id":"uuid","percentage":50}, ...]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_estimate       estimates%ROWTYPE;
  v_invoice_id     uuid;
  v_inv_number     text;
  v_subtotal       numeric := 0;
  v_taxable_total  numeric := 0;
  v_tax_amount     numeric := 0;
  v_total          numeric := 0;
  v_sel            jsonb;
  v_li             line_items%ROWTYPE;
  v_pct            numeric;
  v_pro_qty        numeric;
  v_line_total     numeric;
  v_sort           int := 0;
  v_caller_company uuid;
  i                int;
BEGIN
  -- 1. Authorization: verify caller belongs to the estimate's company
  SELECT company_id INTO v_caller_company
  FROM users
  WHERE auth_id = auth.uid();

  IF v_caller_company IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: user not found';
  END IF;

  -- 2. Validate estimate
  SELECT * INTO v_estimate FROM estimates WHERE id = p_estimate_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Estimate not found';
  END IF;

  IF v_estimate.company_id != v_caller_company THEN
    RAISE EXCEPTION 'Unauthorized: estimate belongs to a different company';
  END IF;

  IF v_estimate.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved estimates can create invoices (current: %)', v_estimate.status;
  END IF;

  -- 3. Gapless invoice number
  v_inv_number := get_next_document_number(v_estimate.company_id, 'invoice');

  -- 4. Create invoice shell (totals filled after line items)
  INSERT INTO invoices (
    company_id, client_id, estimate_id, opportunity_id,
    invoice_number, subtotal, tax_rate, tax_amount, total, balance_due,
    due_date, terms, created_by
  ) VALUES (
    v_estimate.company_id, v_estimate.client_id, p_estimate_id, v_estimate.opportunity_id,
    v_inv_number, 0, COALESCE(v_estimate.tax_rate, 0), 0, 0, 0,
    CURRENT_DATE + 30, v_estimate.terms, v_estimate.created_by
  ) RETURNING id INTO v_invoice_id;

  -- 5. Create prorated line items
  FOR i IN 0 .. jsonb_array_length(p_line_item_selections) - 1
  LOOP
    v_sel := p_line_item_selections -> i;

    SELECT * INTO v_li
    FROM line_items
    WHERE id = (v_sel ->> 'line_item_id')::uuid
      AND estimate_id = p_estimate_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    v_pct := (v_sel ->> 'percentage')::numeric;
    IF v_pct <= 0 OR v_pct > 100 THEN CONTINUE; END IF;

    -- Pro-rate: use stored line_total when available (includes discount),
    -- otherwise compute from quantity * unit_price with discount applied.
    v_pro_qty := ROUND(v_li.quantity * (v_pct / 100.0), 4);
    IF v_li.line_total IS NOT NULL THEN
      v_line_total := ROUND(v_li.line_total * (v_pct / 100.0), 2);
    ELSE
      v_line_total := ROUND(
        v_pro_qty * v_li.unit_price * (1 - COALESCE(v_li.discount_percent, 0) / 100.0),
        2
      );
    END IF;

    v_subtotal := v_subtotal + v_line_total;

    -- Track taxable subtotal separately
    IF COALESCE(v_li.is_taxable, true) THEN
      v_taxable_total := v_taxable_total + v_line_total;
    END IF;

    v_sort := v_sort + 1;

    INSERT INTO line_items (
      company_id, invoice_id, product_id, name, description,
      quantity, unit, unit_price, unit_cost, discount_percent,
      is_taxable, tax_rate_id, line_total, sort_order, category, type
    ) VALUES (
      v_li.company_id, v_invoice_id, v_li.product_id,
      v_li.name,
      COALESCE(NULLIF(v_li.description, ''), v_li.name) || ' (' || v_pct || '% progress)',
      v_pro_qty, v_li.unit, v_li.unit_price,
      v_li.unit_cost, v_li.discount_percent,
      v_li.is_taxable, v_li.tax_rate_id, v_line_total,
      v_sort, v_li.category, v_li.type
    );
  END LOOP;

  -- 6. Guard: do not create empty invoices
  IF v_sort = 0 THEN
    -- Roll back the invoice shell (inside the transaction)
    DELETE FROM invoices WHERE id = v_invoice_id;
    RAISE EXCEPTION 'No valid line items selected for progress invoice';
  END IF;

  -- 7. Calculate totals — tax only on taxable items
  v_tax_amount := ROUND(v_taxable_total * COALESCE(v_estimate.tax_rate, 0) / 100.0, 2);
  v_total      := v_subtotal + v_tax_amount;

  UPDATE invoices SET
    subtotal    = v_subtotal,
    tax_amount  = v_tax_amount,
    total       = v_total,
    balance_due = v_total
  WHERE id = v_invoice_id;

  -- 8. Log activity
  INSERT INTO activities (
    company_id, opportunity_id, client_id, estimate_id, invoice_id,
    type, subject, created_by
  ) VALUES (
    v_estimate.company_id, v_estimate.opportunity_id, v_estimate.client_id,
    p_estimate_id, v_invoice_id, 'invoice_created',
    'Progress invoice ' || v_inv_number || ' created from estimate',
    v_estimate.created_by
  );

  RETURN v_invoice_id;
END;
$$;

