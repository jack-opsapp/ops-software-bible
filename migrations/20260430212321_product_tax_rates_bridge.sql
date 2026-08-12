CREATE TABLE IF NOT EXISTS product_tax_rates (
  product_id    UUID NOT NULL REFERENCES products(id)   ON DELETE CASCADE,
  tax_rate_id   UUID NOT NULL REFERENCES tax_rates(id)  ON DELETE CASCADE,
  PRIMARY KEY (product_id, tax_rate_id)
);
CREATE INDEX IF NOT EXISTS idx_ptr_product  ON product_tax_rates(product_id);
CREATE INDEX IF NOT EXISTS idx_ptr_tax_rate ON product_tax_rates(tax_rate_id);
ALTER TABLE product_tax_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product_tax_rates_company_scope" ON product_tax_rates
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = product_tax_rates.product_id
        AND p.company_id = (SELECT private.get_user_company_id())
    )
  );

INSERT INTO product_tax_rates (product_id, tax_rate_id)
SELECT p.id, tr.id
FROM products p
JOIN tax_rates tr ON tr.company_id = p.company_id AND tr.is_default = TRUE AND tr.is_active = TRUE
WHERE p.is_taxable = TRUE
  AND p.deleted_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM product_tax_rates ptr WHERE ptr.product_id = p.id)
ON CONFLICT DO NOTHING;
