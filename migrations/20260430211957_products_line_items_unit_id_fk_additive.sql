-- ADDITIVE: add unit_id FKs to products + line_items, backfill from text. KEEP unit text.
ALTER TABLE products    ADD COLUMN IF NOT EXISTS unit_id UUID REFERENCES inventory_units(id);
ALTER TABLE line_items  ADD COLUMN IF NOT EXISTS unit_id UUID REFERENCES inventory_units(id);
CREATE INDEX IF NOT EXISTS idx_products_unit_id   ON products(unit_id)   WHERE unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_line_items_unit_id ON line_items(unit_id) WHERE unit_id IS NOT NULL;

UPDATE products p
SET unit_id = u.id
FROM inventory_units u
WHERE u.company_id = p.company_id AND u.deleted_at IS NULL AND p.unit_id IS NULL
  AND (
    (LOWER(p.unit) IN ('each', 'ea')                  AND u.display = 'ea')
    OR (LOWER(p.unit) IN ('hour', 'hr', 'hours')      AND u.display = 'hour')
    OR (LOWER(p.unit) IN ('day', 'd', 'days')         AND u.display = 'day')
    OR (LOWER(p.unit) IN ('linear_ft', 'linear ft', 'linearft', 'lf', 'lin ft', 'linear foot') AND u.display = 'linear ft')
    OR (LOWER(p.unit) IN ('sqft', 'sq ft', 'sq_ft', 'sf', 'square ft', 'square foot') AND u.display = 'sq ft')
    OR (LOWER(p.unit) IN ('sqm', 'sq m', 'sq_m', 'square meter', 'square m') AND u.display = 'sq m')
    OR (LOWER(p.unit) IN ('lb', 'lbs', 'pound', 'pounds') AND u.display = 'lb')
    OR (LOWER(p.unit) IN ('kg', 'kgs', 'kilogram', 'kilograms') AND u.display = 'kg')
    OR (LOWER(p.unit) IN ('gal', 'gals', 'gallon', 'gallons') AND u.display = 'gal')
    OR (LOWER(p.unit) IN ('l', 'litre', 'liter', 'litres', 'liters') AND u.display = 'L')
    OR LOWER(p.unit) = LOWER(u.display)
  );

UPDATE line_items li
SET unit_id = u.id
FROM inventory_units u
WHERE u.company_id = li.company_id AND u.deleted_at IS NULL AND li.unit_id IS NULL
  AND (
    (LOWER(li.unit) IN ('each', 'ea')                  AND u.display = 'ea')
    OR (LOWER(li.unit) IN ('hour', 'hr', 'hours')      AND u.display = 'hour')
    OR (LOWER(li.unit) IN ('day', 'd', 'days')         AND u.display = 'day')
    OR (LOWER(li.unit) IN ('linear_ft', 'linear ft', 'linearft', 'lf', 'lin ft', 'linear foot') AND u.display = 'linear ft')
    OR (LOWER(li.unit) IN ('sqft', 'sq ft', 'sq_ft', 'sf', 'square ft', 'square foot') AND u.display = 'sq ft')
    OR (LOWER(li.unit) IN ('sqm', 'sq m', 'sq_m', 'square meter', 'square m') AND u.display = 'sq m')
    OR (LOWER(li.unit) IN ('lb', 'lbs', 'pound', 'pounds') AND u.display = 'lb')
    OR (LOWER(li.unit) IN ('kg', 'kgs', 'kilogram', 'kilograms') AND u.display = 'kg')
    OR (LOWER(li.unit) IN ('gal', 'gals', 'gallon', 'gallons') AND u.display = 'gal')
    OR (LOWER(li.unit) IN ('l', 'litre', 'liter', 'litres', 'liters') AND u.display = 'L')
    OR LOWER(li.unit) = LOWER(u.display)
  );

DO $$
DECLARE
  unmapped_p INT; unmapped_l INT;
BEGIN
  SELECT COUNT(*) INTO unmapped_p FROM products WHERE unit IS NOT NULL AND unit != '' AND unit_id IS NULL AND deleted_at IS NULL;
  SELECT COUNT(*) INTO unmapped_l FROM line_items WHERE unit IS NOT NULL AND unit != '' AND unit_id IS NULL;
  IF unmapped_p > 0 OR unmapped_l > 0 THEN
    RAISE NOTICE 'Backfill incomplete: % products and % line_items unmapped. Address before applying 1.3b drop.', unmapped_p, unmapped_l;
  END IF;
END $$;
