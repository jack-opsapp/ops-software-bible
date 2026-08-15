-- Enforce SKU uniqueness within a company at the DB layer.
--
-- Catalog variants ship with optional SKUs. When set, the SKU should be
-- unique within the company (different companies are allowed to use the
-- same SKU — they're separate inventories). Soft-deleted rows are
-- excluded so re-creating a variant with the same SKU after delete is
-- still valid.
--
-- Verified safe before applying: 0 existing dupes in catalog_variants
-- (SELECT GROUP BY LOWER(TRIM(sku)) HAVING COUNT(*) > 1 → empty).
--
-- The catalog_import_validate RPC also surfaces SKU collisions early
-- during dry-run preview — leaving it in place because surfacing the
-- error before APPLY is a better UX than waiting for a PostgREST
-- constraint violation. The DB index is the authoritative invariant.

CREATE UNIQUE INDEX IF NOT EXISTS catalog_variants_sku_unique_per_company
  ON catalog_variants (company_id, LOWER(TRIM(sku)))
  WHERE deleted_at IS NULL AND sku IS NOT NULL AND TRIM(sku) <> '';

COMMENT ON INDEX catalog_variants_sku_unique_per_company IS
  'Enforces case-insensitive SKU uniqueness within a company for active variants. Partial index excludes NULL/empty SKUs and soft-deleted rows.';
