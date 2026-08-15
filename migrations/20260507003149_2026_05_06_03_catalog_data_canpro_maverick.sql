BEGIN;

CREATE TEMP TABLE __baseline AS
SELECT 'canpro_items'         AS metric, COUNT(*)::numeric AS value
       FROM public.inventory_items
       WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL
UNION ALL
SELECT 'canpro_qty_sum',      COALESCE(SUM(quantity), 0)
       FROM public.inventory_items
       WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL
UNION ALL
SELECT 'canpro_units',        COUNT(*)
       FROM public.inventory_units
       WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL
UNION ALL
SELECT 'maverick_items',      COUNT(*)
       FROM public.inventory_items
       WHERE company_id='ddee107c-33cd-483e-8278-0f8d8a180181' AND deleted_at IS NULL
UNION ALL
SELECT 'maverick_qty_sum',    COALESCE(SUM(quantity), 0)
       FROM public.inventory_items
       WHERE company_id='ddee107c-33cd-483e-8278-0f8d8a180181' AND deleted_at IS NULL
UNION ALL
SELECT 'maverick_units',      COUNT(*)
       FROM public.inventory_units
       WHERE company_id='ddee107c-33cd-483e-8278-0f8d8a180181' AND deleted_at IS NULL;

INSERT INTO public.catalog_categories (id, company_id, name, parent_id, sort_order) VALUES
    ('11111111-1111-0001-1111-000000000010', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Hardware',         NULL, 10),
    ('11111111-1111-0001-1111-000000000011', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Hardware Level',   '11111111-1111-0001-1111-000000000010', 11),
    ('11111111-1111-0001-1111-000000000012', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Hardware Stair',   '11111111-1111-0001-1111-000000000010', 12),
    ('11111111-1111-0001-1111-000000000020', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Posts',            NULL, 20),
    ('11111111-1111-0001-1111-000000000030', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Side mount',       NULL, 30),
    ('11111111-1111-0001-1111-000000000031', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Topmount',         NULL, 31),
    ('11111111-1111-0001-1111-000000000040', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Rail',             NULL, 40),
    ('11111111-1111-0001-1111-000000000050', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Fasteners',        NULL, 50),
    ('11111111-1111-0001-1111-000000000051', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Screws',           '11111111-1111-0001-1111-000000000050', 51),
    ('11111111-1111-0001-1111-000000000060', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Gates',            NULL, 60);

INSERT INTO public.catalog_categories (id, company_id, name, parent_id, sort_order) VALUES
    ('22222222-2222-0002-2222-000000000010', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Hardware',         NULL, 10),
    ('22222222-2222-0002-2222-000000000011', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Hardware Level',   '22222222-2222-0002-2222-000000000010', 11),
    ('22222222-2222-0002-2222-000000000012', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Hardware Stair',   '22222222-2222-0002-2222-000000000010', 12),
    ('22222222-2222-0002-2222-000000000020', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Posts',            NULL, 20),
    ('22222222-2222-0002-2222-000000000030', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Side mount',       NULL, 30),
    ('22222222-2222-0002-2222-000000000031', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Topmount',         NULL, 31),
    ('22222222-2222-0002-2222-000000000040', 'ddee107c-33cd-483e-8278-0f8d8a180181', 'Rail',             NULL, 40);

INSERT INTO public.catalog_units
    (id, company_id, display, abbreviation, dimension, is_default, sort_order, created_at, updated_at, deleted_at)
SELECT id, company_id, display, abbreviation, dimension, is_default, sort_order, created_at, updated_at, deleted_at
FROM public.inventory_units
WHERE company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181');

CREATE TEMP TABLE __canpro_items AS
SELECT
    i.id AS inventory_item_id,
    i.company_id,
    i.quantity,
    i.warning_threshold,
    i.critical_threshold,
    i.unit_id,
    i.name AS original_name,
    lower(trim(i.name)) AS family_key,
    (SELECT t.name FROM public.inventory_tags t
       JOIN public.inventory_item_tags it ON it.tag_id = t.id
       WHERE it.item_id = i.id AND t.name IN ('Black','White') LIMIT 1) AS color_tag,
    (SELECT t.name FROM public.inventory_tags t
       JOIN public.inventory_item_tags it ON it.tag_id = t.id
       WHERE it.item_id = i.id AND t.name IN ('Topmount','Side mount','Hardware Level','Hardware Stair') LIMIT 1) AS mount_tag,
    (SELECT t.name FROM public.inventory_tags t
       JOIN public.inventory_item_tags it ON it.tag_id = t.id
       WHERE it.item_id = i.id AND t.name IN ('Screws','Rail','Gate') LIMIT 1) AS klass_tag
FROM public.inventory_items i
WHERE i.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND i.deleted_at IS NULL;

CREATE TEMP TABLE __canpro_families AS
SELECT
    family_key,
    MIN(original_name) AS canonical_name,
    array_agg(DISTINCT mount_tag ORDER BY mount_tag) FILTER (WHERE mount_tag IS NOT NULL) AS mounts,
    array_agg(DISTINCT color_tag ORDER BY color_tag) FILTER (WHERE color_tag IS NOT NULL) AS colors,
    array_agg(DISTINCT klass_tag ORDER BY klass_tag) FILTER (WHERE klass_tag IS NOT NULL) AS klasses,
    md5('canpro_fam:' || family_key)::uuid AS family_id
FROM __canpro_items
GROUP BY family_key;

ALTER TABLE __canpro_families ADD COLUMN category_id uuid;

UPDATE __canpro_families SET category_id = CASE
    WHEN klasses IS NOT NULL AND 'Rail'   = ANY(klasses) THEN '11111111-1111-0001-1111-000000000040'::uuid
    WHEN klasses IS NOT NULL AND 'Screws' = ANY(klasses) THEN '11111111-1111-0001-1111-000000000051'::uuid
    WHEN klasses IS NOT NULL AND 'Gate'   = ANY(klasses) THEN '11111111-1111-0001-1111-000000000060'::uuid
    WHEN mounts IS NOT NULL AND array_length(mounts, 1) > 1 THEN '11111111-1111-0001-1111-000000000020'::uuid
    WHEN mounts IS NOT NULL AND 'Hardware Level' = ANY(mounts) AND array_length(mounts, 1) = 1 THEN '11111111-1111-0001-1111-000000000011'::uuid
    WHEN mounts IS NOT NULL AND 'Hardware Stair' = ANY(mounts) AND array_length(mounts, 1) = 1 THEN '11111111-1111-0001-1111-000000000012'::uuid
    WHEN mounts IS NOT NULL AND 'Topmount'       = ANY(mounts) AND array_length(mounts, 1) = 1 THEN '11111111-1111-0001-1111-000000000031'::uuid
    WHEN mounts IS NOT NULL AND 'Side mount'     = ANY(mounts) AND array_length(mounts, 1) = 1 THEN '11111111-1111-0001-1111-000000000030'::uuid
    ELSE '11111111-1111-0001-1111-000000000020'::uuid
END;

INSERT INTO public.catalog_items
    (id, company_id, category_id, name, default_unit_id, is_active, created_at, updated_at)
SELECT
    f.family_id,
    'a612edc0-5c18-4c4d-af97-55b9410dd077',
    f.category_id,
    f.canonical_name,
    NULL,
    true,
    now(),
    now()
FROM __canpro_families f;

INSERT INTO public.catalog_options (id, catalog_item_id, name, sort_order)
SELECT
    md5('canpro_opt_color:' || family_key)::uuid,
    family_id,
    'Color',
    10
FROM __canpro_families
WHERE colors IS NOT NULL AND array_length(colors, 1) > 0;

INSERT INTO public.catalog_options (id, catalog_item_id, name, sort_order)
SELECT
    md5('canpro_opt_mount:' || family_key)::uuid,
    family_id,
    'Mount Type',
    20
FROM __canpro_families
WHERE mounts IS NOT NULL AND array_length(mounts, 1) > 1;

INSERT INTO public.catalog_option_values (id, option_id, value, sort_order)
SELECT DISTINCT
    md5('canpro_optval_color:' || f.family_key || ':' || c.color)::uuid,
    md5('canpro_opt_color:' || f.family_key)::uuid,
    c.color,
    CASE c.color WHEN 'Black' THEN 10 WHEN 'White' THEN 20 ELSE 30 END
FROM __canpro_families f, unnest(f.colors) AS c(color);

INSERT INTO public.catalog_option_values (id, option_id, value, sort_order)
SELECT DISTINCT
    md5('canpro_optval_mount:' || f.family_key || ':' || m.mount)::uuid,
    md5('canpro_opt_mount:' || f.family_key)::uuid,
    m.mount,
    CASE m.mount
        WHEN 'Topmount'       THEN 10
        WHEN 'Side mount'     THEN 20
        WHEN 'Hardware Level' THEN 30
        WHEN 'Hardware Stair' THEN 40
        ELSE 50
    END
FROM __canpro_families f, unnest(f.mounts) AS m(mount)
WHERE f.mounts IS NOT NULL AND array_length(f.mounts, 1) > 1;

INSERT INTO public.catalog_variants
    (id, company_id, catalog_item_id, sku, quantity, warning_threshold, critical_threshold, unit_id, is_active, created_at, updated_at)
SELECT
    ci.inventory_item_id,
    ci.company_id,
    f.family_id,
    NULL,
    ci.quantity,
    ci.warning_threshold,
    ci.critical_threshold,
    ci.unit_id,
    true,
    now(),
    now()
FROM __canpro_items ci
JOIN __canpro_families f USING (family_key);

INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
SELECT
    ci.inventory_item_id,
    md5('canpro_optval_color:' || ci.family_key || ':' || ci.color_tag)::uuid
FROM __canpro_items ci
WHERE ci.color_tag IS NOT NULL;

INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
SELECT
    ci.inventory_item_id,
    md5('canpro_optval_mount:' || ci.family_key || ':' || ci.mount_tag)::uuid
FROM __canpro_items ci
JOIN __canpro_families f USING (family_key)
WHERE ci.mount_tag IS NOT NULL
  AND f.mounts IS NOT NULL AND array_length(f.mounts, 1) > 1;

CREATE TEMP TABLE __maverick_items AS
SELECT
    i.id AS inventory_item_id,
    i.company_id,
    i.quantity,
    i.warning_threshold,
    i.critical_threshold,
    i.unit_id,
    i.name AS original_name,
    lower(trim(i.name)) AS family_key,
    (SELECT REPLACE(t.name, ' Qty', '')
       FROM public.inventory_tags t
       JOIN public.inventory_item_tags it ON it.tag_id = t.id
       WHERE it.item_id = i.id AND t.name IN ('Black Qty','White Qty') LIMIT 1) AS color_norm
FROM public.inventory_items i
WHERE i.company_id='ddee107c-33cd-483e-8278-0f8d8a180181' AND i.deleted_at IS NULL;

CREATE TEMP TABLE __maverick_families AS
SELECT
    family_key,
    MIN(original_name) AS canonical_name,
    array_agg(DISTINCT color_norm ORDER BY color_norm) FILTER (WHERE color_norm IS NOT NULL) AS colors,
    md5('maverick_fam:' || family_key)::uuid AS family_id
FROM __maverick_items
GROUP BY family_key;

ALTER TABLE __maverick_families ADD COLUMN category_id uuid;

UPDATE __maverick_families SET category_id = CASE
    WHEN family_key LIKE 'sidemount %'  THEN '22222222-2222-0002-2222-000000000030'::uuid
    WHEN family_key LIKE 'topmount %'   THEN '22222222-2222-0002-2222-000000000031'::uuid
    WHEN family_key LIKE 'stair %'      THEN '22222222-2222-0002-2222-000000000012'::uuid
    WHEN family_key LIKE 'level %'      THEN '22222222-2222-0002-2222-000000000011'::uuid
    WHEN family_key LIKE 'picket %'     THEN '22222222-2222-0002-2222-000000000040'::uuid
    WHEN family_key LIKE 'glass rail%'  THEN '22222222-2222-0002-2222-000000000040'::uuid
    WHEN family_key = 'windwall sleeve in' THEN '22222222-2222-0002-2222-000000000011'::uuid
    WHEN family_key = 'blank adapter'   THEN '22222222-2222-0002-2222-000000000011'::uuid
    WHEN family_key = '45 degree bracket' THEN '22222222-2222-0002-2222-000000000011'::uuid
    ELSE '22222222-2222-0002-2222-000000000020'::uuid
END;

INSERT INTO public.catalog_items
    (id, company_id, category_id, name, default_unit_id, is_active, created_at, updated_at)
SELECT
    f.family_id,
    'ddee107c-33cd-483e-8278-0f8d8a180181',
    f.category_id,
    f.canonical_name,
    NULL,
    true,
    now(),
    now()
FROM __maverick_families f;

INSERT INTO public.catalog_options (id, catalog_item_id, name, sort_order)
SELECT
    md5('maverick_opt_color:' || family_key)::uuid,
    family_id,
    'Color',
    10
FROM __maverick_families
WHERE colors IS NOT NULL AND array_length(colors, 1) > 0;

INSERT INTO public.catalog_option_values (id, option_id, value, sort_order)
SELECT DISTINCT
    md5('maverick_optval_color:' || f.family_key || ':' || c.color)::uuid,
    md5('maverick_opt_color:' || f.family_key)::uuid,
    c.color,
    CASE c.color WHEN 'Black' THEN 10 WHEN 'White' THEN 20 ELSE 30 END
FROM __maverick_families f, unnest(f.colors) AS c(color);

INSERT INTO public.catalog_variants
    (id, company_id, catalog_item_id, sku, quantity, warning_threshold, critical_threshold, unit_id, is_active, created_at, updated_at)
SELECT
    mi.inventory_item_id,
    mi.company_id,
    f.family_id,
    NULL,
    mi.quantity,
    mi.warning_threshold,
    mi.critical_threshold,
    mi.unit_id,
    true,
    now(),
    now()
FROM __maverick_items mi
JOIN __maverick_families f USING (family_key);

INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
SELECT
    mi.inventory_item_id,
    md5('maverick_optval_color:' || mi.family_key || ':' || mi.color_norm)::uuid
FROM __maverick_items mi
WHERE mi.color_norm IS NOT NULL;

DO $$
DECLARE
    canpro_pre_items numeric;
    canpro_pre_qty numeric;
    canpro_post_variants numeric;
    canpro_post_qty numeric;
    canpro_post_families numeric;
    maverick_pre_items numeric;
    maverick_pre_qty numeric;
    maverick_post_variants numeric;
    maverick_post_qty numeric;
    maverick_post_families numeric;
BEGIN
    SELECT value INTO canpro_pre_items   FROM __baseline WHERE metric='canpro_items';
    SELECT value INTO canpro_pre_qty     FROM __baseline WHERE metric='canpro_qty_sum';
    SELECT value INTO maverick_pre_items FROM __baseline WHERE metric='maverick_items';
    SELECT value INTO maverick_pre_qty   FROM __baseline WHERE metric='maverick_qty_sum';

    SELECT COUNT(*), COALESCE(SUM(quantity), 0)
      INTO canpro_post_variants, canpro_post_qty
      FROM public.catalog_variants
     WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL;

    SELECT COUNT(*) INTO canpro_post_families
      FROM public.catalog_items
     WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL;

    SELECT COUNT(*), COALESCE(SUM(quantity), 0)
      INTO maverick_post_variants, maverick_post_qty
      FROM public.catalog_variants
     WHERE company_id='ddee107c-33cd-483e-8278-0f8d8a180181' AND deleted_at IS NULL;

    SELECT COUNT(*) INTO maverick_post_families
      FROM public.catalog_items
     WHERE company_id='ddee107c-33cd-483e-8278-0f8d8a180181' AND deleted_at IS NULL;

    IF canpro_post_variants <> canpro_pre_items THEN
        RAISE EXCEPTION 'Canpro variant count mismatch: pre=%, post=%', canpro_pre_items, canpro_post_variants;
    END IF;
    IF canpro_post_qty <> canpro_pre_qty THEN
        RAISE EXCEPTION 'Canpro qty sum mismatch: pre=%, post=%', canpro_pre_qty, canpro_post_qty;
    END IF;
    IF maverick_post_variants <> maverick_pre_items THEN
        RAISE EXCEPTION 'Maverick variant count mismatch: pre=%, post=%', maverick_pre_items, maverick_post_variants;
    END IF;
    IF maverick_post_qty <> maverick_pre_qty THEN
        RAISE EXCEPTION 'Maverick qty sum mismatch: pre=%, post=%', maverick_pre_qty, maverick_post_qty;
    END IF;

    RAISE NOTICE 'Migration verification: Canpro % families / % variants / qty=%; Maverick % families / % variants / qty=%',
        canpro_post_families, canpro_post_variants, canpro_post_qty,
        maverick_post_families, maverick_post_variants, maverick_post_qty;
END $$;

UPDATE public.inventory_items SET deleted_at = now()
 WHERE company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
   AND deleted_at IS NULL;
UPDATE public.inventory_tags SET deleted_at = now()
 WHERE company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
   AND deleted_at IS NULL;
UPDATE public.inventory_units SET deleted_at = now()
 WHERE company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
   AND deleted_at IS NULL;

DROP TABLE __baseline;
DROP TABLE __canpro_items;
DROP TABLE __canpro_families;
DROP TABLE __maverick_items;
DROP TABLE __maverick_families;

COMMIT;
