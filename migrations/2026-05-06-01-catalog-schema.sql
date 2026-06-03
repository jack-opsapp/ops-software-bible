-- 2026-05-06-01-catalog-schema.sql
-- Catalog variant model — schema DDL only.
--
-- Origin: docs/superpowers/specs/2026-05-06-ios-catalog-variant-model-design.md
--         docs/superpowers/plans/2026-05-06-ios-catalog-variant-model.md (Phase 1 Task 2)
--
-- Companion migrations:
--   02 — views over catalog_* + INSTEAD OF triggers + base_price↔default_price mirror trigger
--   03 — bespoke per-company data migration (Canpro + Maverick)
--   04 — permission rename (inventory.* → catalog.*)
--
-- Apply order: 01 → 03 → 02 → 04. (02 must run AFTER data migration so it can DROP legacy tables.)

BEGIN;

-- =====================================================
-- 1. catalog_categories  (nested, parent_id self-FK)
-- =====================================================
CREATE TABLE public.catalog_categories (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id                  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name                        text NOT NULL,
    parent_id                   uuid REFERENCES public.catalog_categories(id) ON DELETE SET NULL,
    sort_order                  integer NOT NULL DEFAULT 0,
    color_hex                   text,
    default_warning_threshold   double precision,
    default_critical_threshold  double precision,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz
);
CREATE INDEX idx_catalog_categories_company_parent
    ON public.catalog_categories(company_id, parent_id) WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION private.catalog_categories_no_cycle()
RETURNS trigger AS $$
DECLARE
    cur_id uuid := NEW.parent_id;
    depth integer := 0;
BEGIN
    WHILE cur_id IS NOT NULL LOOP
        IF cur_id = NEW.id THEN
            RAISE EXCEPTION 'catalog_categories cycle detected via parent_id';
        END IF;
        SELECT parent_id INTO cur_id FROM public.catalog_categories WHERE id = cur_id;
        depth := depth + 1;
        IF depth > 50 THEN
            RAISE EXCEPTION 'catalog_categories parent chain exceeds 50 levels';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_catalog_categories_no_cycle
    BEFORE INSERT OR UPDATE OF parent_id ON public.catalog_categories
    FOR EACH ROW EXECUTE FUNCTION private.catalog_categories_no_cycle();

ALTER TABLE public.catalog_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_categories
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 2. catalog_units
-- =====================================================
CREATE TABLE public.catalog_units (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id   uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    display      text NOT NULL,
    abbreviation text,
    dimension    text NOT NULL DEFAULT 'count',
    is_default   boolean NOT NULL DEFAULT false,
    sort_order   integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    deleted_at   timestamptz
);
CREATE INDEX idx_catalog_units_company
    ON public.catalog_units(company_id, sort_order) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_units ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_units
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 3. catalog_items  (variant families)
-- =====================================================
CREATE TABLE public.catalog_items (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id                  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    category_id                 uuid REFERENCES public.catalog_categories(id) ON DELETE SET NULL,
    name                        text NOT NULL,
    description                 text,
    default_price               numeric,
    default_unit_cost           numeric,
    default_warning_threshold   double precision,
    default_critical_threshold  double precision,
    default_unit_id             uuid REFERENCES public.catalog_units(id) ON DELETE SET NULL,
    image_url                   text,
    notes                       text,
    is_active                   boolean NOT NULL DEFAULT true,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz
);
CREATE INDEX idx_catalog_items_company_category
    ON public.catalog_items(company_id, category_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_items_company_active
    ON public.catalog_items(company_id, is_active) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_items
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 4. catalog_options  (variant axes per family)
-- =====================================================
CREATE TABLE public.catalog_options (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_item_id   uuid NOT NULL REFERENCES public.catalog_items(id) ON DELETE CASCADE,
    name              text NOT NULL,
    sort_order        integer NOT NULL DEFAULT 0,
    created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_catalog_options_item ON public.catalog_options(catalog_item_id, sort_order);

ALTER TABLE public.catalog_options ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_options
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_items i
                WHERE i.id = catalog_options.catalog_item_id
                  AND i.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 5. catalog_option_values
-- =====================================================
CREATE TABLE public.catalog_option_values (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    option_id   uuid NOT NULL REFERENCES public.catalog_options(id) ON DELETE CASCADE,
    value       text NOT NULL,
    sort_order  integer NOT NULL DEFAULT 0,
    UNIQUE (option_id, value)
);

ALTER TABLE public.catalog_option_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_option_values
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_options o
                JOIN public.catalog_items i ON i.id = o.catalog_item_id
                WHERE o.id = catalog_option_values.option_id
                  AND i.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 6. catalog_variants  (the SKUs)
-- =====================================================
CREATE TABLE public.catalog_variants (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    catalog_item_id     uuid NOT NULL REFERENCES public.catalog_items(id) ON DELETE CASCADE,
    sku                 text,
    quantity            double precision NOT NULL DEFAULT 0,
    price_override      numeric,
    unit_cost_override  numeric,
    warning_threshold   double precision,
    critical_threshold  double precision,
    unit_id             uuid REFERENCES public.catalog_units(id) ON DELETE SET NULL,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);
CREATE INDEX idx_catalog_variants_item
    ON public.catalog_variants(catalog_item_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_variants_company
    ON public.catalog_variants(company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_variants_sku
    ON public.catalog_variants(sku) WHERE deleted_at IS NULL AND sku IS NOT NULL;

ALTER TABLE public.catalog_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_variants
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 7. catalog_variant_option_values  (M2M)
-- =====================================================
CREATE TABLE public.catalog_variant_option_values (
    variant_id       uuid NOT NULL REFERENCES public.catalog_variants(id) ON DELETE CASCADE,
    option_value_id  uuid NOT NULL REFERENCES public.catalog_option_values(id) ON DELETE CASCADE,
    PRIMARY KEY (variant_id, option_value_id)
);
CREATE INDEX idx_cvov_value ON public.catalog_variant_option_values(option_value_id);

ALTER TABLE public.catalog_variant_option_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_variant_option_values
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_variants v
                WHERE v.id = catalog_variant_option_values.variant_id
                  AND v.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 8. catalog_tags  (free-form labels at family level)
-- =====================================================
CREATE TABLE public.catalog_tags (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name                text NOT NULL,
    warning_threshold   double precision,
    critical_threshold  double precision,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);
CREATE UNIQUE INDEX idx_catalog_tags_company_name_active
    ON public.catalog_tags(company_id, lower(name)) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_tags_company
    ON public.catalog_tags(company_id) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_tags
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 9. catalog_item_tags  (M2M family ↔ tag)
-- =====================================================
CREATE TABLE public.catalog_item_tags (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_item_id uuid NOT NULL REFERENCES public.catalog_items(id) ON DELETE CASCADE,
    tag_id          uuid NOT NULL REFERENCES public.catalog_tags(id) ON DELETE CASCADE,
    UNIQUE (catalog_item_id, tag_id)
);
CREATE INDEX idx_cit_tag ON public.catalog_item_tags(tag_id);

ALTER TABLE public.catalog_item_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_item_tags
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_items i
                WHERE i.id = catalog_item_tags.catalog_item_id
                  AND i.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 10. catalog_snapshots
-- =====================================================
CREATE TABLE public.catalog_snapshots (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    is_automatic  boolean NOT NULL DEFAULT false,
    item_count    integer NOT NULL DEFAULT 0,
    notes         text,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_catalog_snapshots_company
    ON public.catalog_snapshots(company_id, created_at DESC);

ALTER TABLE public.catalog_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_snapshots
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 11. catalog_snapshot_items
-- =====================================================
CREATE TABLE public.catalog_snapshot_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id         uuid NOT NULL REFERENCES public.catalog_snapshots(id) ON DELETE CASCADE,
    original_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE SET NULL,
    family_name         text NOT NULL,
    variant_label       text,
    quantity            double precision NOT NULL DEFAULT 0,
    unit_display        text,
    sku                 text,
    description         text
);
CREATE INDEX idx_catalog_snapshot_items_snap
    ON public.catalog_snapshot_items(snapshot_id);

ALTER TABLE public.catalog_snapshot_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_snapshot_items
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_snapshots s
                WHERE s.id = catalog_snapshot_items.snapshot_id
                  AND s.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 12. catalog_orders
-- =====================================================
CREATE TABLE public.catalog_orders (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id               uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    status                   text NOT NULL DEFAULT 'draft'
                             CHECK (status IN ('suggested','draft','sent','fulfilled','cancelled')),
    title                    text,
    supplier_name            text,
    supplier_contact         text,
    expected_delivery_date   date,
    notes                    text,
    created_by_id            uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    sent_at                  timestamptz,
    fulfilled_at             timestamptz,
    cancelled_at             timestamptz,
    deleted_at               timestamptz
);
CREATE INDEX idx_catalog_orders_company_status
    ON public.catalog_orders(company_id, status) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_orders
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 13. catalog_order_items
-- =====================================================
CREATE TABLE public.catalog_order_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id            uuid NOT NULL REFERENCES public.catalog_orders(id) ON DELETE CASCADE,
    catalog_variant_id  uuid NOT NULL REFERENCES public.catalog_variants(id) ON DELETE RESTRICT,
    quantity_requested  double precision NOT NULL,
    cost_per_unit       numeric,
    notes               text
);
CREATE INDEX idx_catalog_order_items_order ON public.catalog_order_items(order_id);
CREATE INDEX idx_catalog_order_items_variant ON public.catalog_order_items(catalog_variant_id);

ALTER TABLE public.catalog_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_order_items
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_orders o
                WHERE o.id = catalog_order_items.order_id
                  AND o.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 14. company_default_products
-- =====================================================
CREATE TABLE public.company_default_products (
    company_id     uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    component_type text NOT NULL CHECK (component_type IN ('railing','deck_board','stair_set','gate','post_set')),
    product_id     uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, component_type)
);

ALTER TABLE public.company_default_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.company_default_products
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 15. products  — extension columns
-- =====================================================
ALTER TABLE public.products
    ADD COLUMN base_price    numeric NOT NULL DEFAULT 0,
    ADD COLUMN pricing_unit  text    NOT NULL DEFAULT 'each'
        CHECK (pricing_unit IN ('each','flat_rate','linear_foot','sqft','hour','day'));

UPDATE public.products SET base_price = default_price;
-- The base_price ↔ default_price mirror trigger lives in 02-catalog-views-triggers.sql.

-- =====================================================
-- 16. product_options
-- =====================================================
CREATE TABLE public.product_options (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id               uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    name                     text NOT NULL,
    kind                     text NOT NULL CHECK (kind IN ('select','integer','boolean')),
    affects_price            boolean NOT NULL DEFAULT false,
    affects_recipe           boolean NOT NULL DEFAULT false,
    required                 boolean NOT NULL DEFAULT true,
    default_value            text,
    option_default_source    text,
    sort_order               integer NOT NULL DEFAULT 0,
    created_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_product_options_product
    ON public.product_options(product_id, sort_order);

ALTER TABLE public.product_options ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.product_options
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.products p
                WHERE p.id = product_options.product_id
                  AND p.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 17. product_option_values
-- =====================================================
CREATE TABLE public.product_option_values (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    option_id   uuid NOT NULL REFERENCES public.product_options(id) ON DELETE CASCADE,
    value       text NOT NULL,
    sort_order  integer NOT NULL DEFAULT 0,
    UNIQUE (option_id, value)
);

ALTER TABLE public.product_option_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.product_option_values
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.product_options o
                JOIN public.products p ON p.id = o.product_id
                WHERE o.id = product_option_values.option_id
                  AND p.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 18. product_pricing_modifiers
-- =====================================================
CREATE TABLE public.product_pricing_modifiers (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id        uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    option_id         uuid NOT NULL REFERENCES public.product_options(id) ON DELETE CASCADE,
    trigger_value_id  uuid REFERENCES public.product_option_values(id) ON DELETE CASCADE,
    trigger_int_min   integer,
    trigger_int_max   integer,
    modifier_kind     text NOT NULL CHECK (modifier_kind IN ('add_per_unit','add_flat','add_per_count','multiply_unit_price')),
    amount            numeric NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_product_pricing_modifiers_product
    ON public.product_pricing_modifiers(product_id);

ALTER TABLE public.product_pricing_modifiers ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.product_pricing_modifiers
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.products p
                WHERE p.id = product_pricing_modifiers.product_id
                  AND p.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 19. product_materials  — extension columns (recipe rules)
-- =====================================================
-- Existing PK is composite (product_id, inventory_item_id). Drop it; replace
-- with a synthetic id PK so the row is uniquely addressable as a recipe row.
-- product_materials currently has 0 rows globally, so this is non-destructive.
ALTER TABLE public.product_materials DROP CONSTRAINT product_materials_pkey;
ALTER TABLE public.product_materials
    ADD COLUMN id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ADD COLUMN catalog_variant_id   uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT,
    ADD COLUMN catalog_item_id      uuid REFERENCES public.catalog_items(id) ON DELETE RESTRICT,
    ADD COLUMN variant_selector     jsonb,
    ADD COLUMN scaled_by_option_id  uuid REFERENCES public.product_options(id) ON DELETE SET NULL,
    ADD COLUMN unit_id              uuid REFERENCES public.catalog_units(id) ON DELETE SET NULL;

ALTER TABLE public.product_materials
    ALTER COLUMN inventory_item_id DROP NOT NULL;

ALTER TABLE public.product_materials
    ADD CONSTRAINT chk_product_materials_pin_xor_family
    CHECK (
        (catalog_variant_id IS NOT NULL AND catalog_item_id IS NULL)
        OR
        (catalog_variant_id IS NULL AND catalog_item_id IS NOT NULL)
        OR
        (catalog_variant_id IS NULL AND catalog_item_id IS NULL AND inventory_item_id IS NOT NULL)
    );

-- =====================================================
-- 20. line_items  — snapshot fields for configurable Products
-- =====================================================
ALTER TABLE public.line_items
    ADD COLUMN configured_options       jsonb,
    ADD COLUMN resolved_unit_price      numeric,
    ADD COLUMN resolved_options_label   text;

-- =====================================================
-- 21. inventory_deductions  — add catalog_variant_id (legacy column stays)
-- =====================================================
ALTER TABLE public.inventory_deductions
    ADD COLUMN catalog_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT;

-- =====================================================
-- 22. task_materials  — add catalog_variant_id
-- =====================================================
ALTER TABLE public.task_materials
    ADD COLUMN catalog_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT;

ALTER TABLE public.task_materials
    ALTER COLUMN inventory_item_id DROP NOT NULL;

-- =====================================================
-- 23. line_item_materials  — add catalog_variant_id
-- =====================================================
ALTER TABLE public.line_item_materials
    ADD COLUMN catalog_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT;

ALTER TABLE public.line_item_materials
    ALTER COLUMN inventory_item_id DROP NOT NULL;

COMMIT;
