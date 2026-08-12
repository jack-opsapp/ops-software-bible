-- Bug 164e0595 — New Product Sheet redesign.
-- Adds an optional FK from a Material product to a stock catalog_item so the
-- two catalogs can be linked from the iOS create flow. Nullable + ON DELETE
-- SET NULL keeps the column safe for old App Store iOS builds (which neither
-- read nor write it) and prevents stock-item deletes from cascading into the
-- priced product. Auto-deduction on sale is deferred to P1-28.

ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS linked_catalog_item_id uuid NULL
  REFERENCES public.catalog_items(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS products_linked_catalog_item_id_idx
  ON public.products (linked_catalog_item_id)
  WHERE linked_catalog_item_id IS NOT NULL;

COMMENT ON COLUMN public.products.linked_catalog_item_id IS
  'Optional FK to catalog_items.id. Set when a Material-category Product is linked to a stock-tracked inventory item via the iOS // SHOW IN STOCK toggle. Auto-deduction on sale is wired in the P1-28 stock overhaul.';
