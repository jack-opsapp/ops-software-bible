-- 1. KIND classification
ALTER TABLE products ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'service'
  CHECK (kind IN ('service', 'material', 'package'));
UPDATE products SET kind = CASE
  WHEN type = 'LABOR'    THEN 'service'
  WHEN type = 'MATERIAL' THEN 'material'
  WHEN type = 'OTHER'    THEN 'service'
  ELSE 'service'
END WHERE kind = 'service';
CREATE INDEX IF NOT EXISTS idx_products_kind ON products(company_id, kind);

-- 2. SKU
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_products_sku_per_company
  ON products(company_id, sku) WHERE sku IS NOT NULL AND deleted_at IS NULL;

-- 3. Favorite flag
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_products_favorite
  ON products(company_id, is_favorite) WHERE is_favorite = TRUE AND deleted_at IS NULL;

-- 4. Minimum charges
ALTER TABLE products ADD COLUMN IF NOT EXISTS minimum_charge NUMERIC;
ALTER TABLE products ADD COLUMN IF NOT EXISTS minimum_quantity NUMERIC;

-- 5. show_bom_on_estimate
ALTER TABLE products ADD COLUMN IF NOT EXISTS show_bom_on_estimate BOOLEAN NOT NULL DEFAULT FALSE;

-- 6. show_in_storefront
ALTER TABLE products ADD COLUMN IF NOT EXISTS show_in_storefront BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_products_storefront
  ON products(company_id, show_in_storefront) WHERE show_in_storefront = TRUE AND deleted_at IS NULL;

-- 7. tiered_pricing JSONB
ALTER TABLE products ADD COLUMN IF NOT EXISTS tiered_pricing JSONB NOT NULL DEFAULT '{}';
COMMENT ON COLUMN products.tiered_pricing IS
  'JSONB of tier => unit_price overrides. Example: {"general": 85.00, "contractor": 72.00}.
   Empty {} means fall back to default_price for all tiers. Tier name comes from clients.pricing_tier.';

-- 8. SKU auto-generator RPC
CREATE OR REPLACE FUNCTION generate_product_sku(
  p_company_id UUID,
  p_kind       TEXT,
  p_category   TEXT
) RETURNS TEXT AS $$
DECLARE
  kind_prefix TEXT;
  cat_prefix  TEXT;
  next_seq    INT;
  candidate   TEXT;
BEGIN
  kind_prefix := CASE p_kind
    WHEN 'service'  THEN 'SVC'
    WHEN 'material' THEN 'MAT'
    WHEN 'package'  THEN 'PKG'
    ELSE 'PRD'
  END;

  IF p_category IS NULL OR LENGTH(TRIM(p_category)) = 0 THEN
    cat_prefix := 'GEN';
  ELSE
    cat_prefix := UPPER(LEFT(REGEXP_REPLACE(p_category, '[^A-Za-z0-9]', '', 'g'), 3));
    IF LENGTH(cat_prefix) < 3 THEN
      cat_prefix := RPAD(cat_prefix, 3, 'X');
    END IF;
  END IF;

  SELECT COALESCE(MAX(CAST(SUBSTRING(sku FROM '\d+$') AS INTEGER)), 0) + 1
  INTO next_seq
  FROM products
  WHERE company_id = p_company_id
    AND sku LIKE kind_prefix || '-' || cat_prefix || '-%';

  candidate := kind_prefix || '-' || cat_prefix || '-' || LPAD(next_seq::TEXT, 6, '0');
  RETURN candidate;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
