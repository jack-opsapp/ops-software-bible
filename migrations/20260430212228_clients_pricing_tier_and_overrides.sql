-- 1. clients.pricing_tier
ALTER TABLE clients ADD COLUMN IF NOT EXISTS pricing_tier TEXT NOT NULL DEFAULT 'general';
COMMENT ON COLUMN clients.pricing_tier IS
  'Tier name that resolves against products.tiered_pricing JSONB. Common values: general, contractor, vip. Free-text — companies define their own tiers.';

-- 2. client_product_overrides
CREATE TABLE IF NOT EXISTS client_product_overrides (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  client_id    UUID NOT NULL REFERENCES clients(id)   ON DELETE CASCADE,
  product_id   UUID NOT NULL REFERENCES products(id)  ON DELETE CASCADE,
  unit_price   NUMERIC NOT NULL,
  notes        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (client_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_cpo_company  ON client_product_overrides(company_id);
CREATE INDEX IF NOT EXISTS idx_cpo_client   ON client_product_overrides(client_id);
CREATE INDEX IF NOT EXISTS idx_cpo_product  ON client_product_overrides(product_id);
ALTER TABLE client_product_overrides ENABLE ROW LEVEL SECURITY;
CREATE POLICY "client_product_overrides_company_scope" ON client_product_overrides
  FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- 3. resolve_product_price RPC
CREATE OR REPLACE FUNCTION resolve_product_price(
  p_product_id UUID,
  p_client_id  UUID
) RETURNS NUMERIC AS $$
DECLARE
  override_price NUMERIC;
  tier_name      TEXT;
  tier_price     NUMERIC;
  default_p      NUMERIC;
BEGIN
  SELECT unit_price INTO override_price
  FROM client_product_overrides
  WHERE client_id = p_client_id AND product_id = p_product_id;
  IF override_price IS NOT NULL THEN
    RETURN override_price;
  END IF;

  SELECT pricing_tier INTO tier_name FROM clients WHERE id = p_client_id;
  SELECT (tiered_pricing ->> tier_name)::NUMERIC, default_price
    INTO tier_price, default_p
    FROM products WHERE id = p_product_id;

  IF tier_price IS NOT NULL THEN
    RETURN tier_price;
  END IF;
  RETURN default_p;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
