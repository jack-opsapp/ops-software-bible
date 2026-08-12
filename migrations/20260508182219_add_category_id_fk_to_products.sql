-- Adds a real FK from products to catalog_categories so the Add Product
-- flow on iOS can stop relying on the legacy free-text `category` column.
-- Additive only: nullable column, ON DELETE SET NULL so legacy rows and
-- categories deleted out from under a product don't break.
--
-- Mirrors the unit_id FK pattern that already exists on this table.
-- The legacy `category` text column stays in place for rows that haven't
-- been migrated yet — new writes from the iOS catalog UI populate both.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS category_id uuid
    REFERENCES catalog_categories(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_products_category_id
  ON products(category_id)
  WHERE category_id IS NOT NULL;

COMMENT ON COLUMN products.category_id IS
  'FK to catalog_categories.id. Nullable for legacy rows still on the free-text `category` column. New iOS catalog writes populate both for read fallback compatibility; the FK is the authoritative source going forward.';
