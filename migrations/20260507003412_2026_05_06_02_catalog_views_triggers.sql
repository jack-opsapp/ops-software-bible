BEGIN;

DO $$
DECLARE
    orphan_items integer;
    orphan_tags integer;
BEGIN
    SELECT COUNT(*) INTO orphan_items FROM public.inventory_items WHERE deleted_at IS NULL;
    SELECT COUNT(*) INTO orphan_tags  FROM public.inventory_tags  WHERE deleted_at IS NULL;
    IF orphan_items > 0 OR orphan_tags > 0 THEN
        RAISE EXCEPTION 'Refusing to drop legacy tables: % active inventory_items, % active inventory_tags exist', orphan_items, orphan_tags;
    END IF;
END $$;

DROP TABLE public.inventory_item_tags      CASCADE;
DROP TABLE public.inventory_snapshot_items CASCADE;
DROP TABLE public.inventory_snapshots      CASCADE;
DROP TABLE public.inventory_items          CASCADE;
DROP TABLE public.inventory_tags           CASCADE;
DROP TABLE public.inventory_units          CASCADE;

CREATE VIEW public.inventory_units AS
    SELECT id, company_id, display, is_default, sort_order, created_at, updated_at, deleted_at,
           abbreviation, dimension
    FROM public.catalog_units;

CREATE OR REPLACE FUNCTION private.iv_inventory_units_insert()
RETURNS trigger AS $func$
BEGIN
    INSERT INTO public.catalog_units (id, company_id, display, abbreviation, dimension, is_default, sort_order, created_at, updated_at, deleted_at)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), NEW.company_id, NEW.display,
            NEW.abbreviation, COALESCE(NEW.dimension, 'count'),
            COALESCE(NEW.is_default, false), COALESCE(NEW.sort_order, 0),
            COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at);
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_units_insert INSTEAD OF INSERT ON public.inventory_units
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_units_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_units_update()
RETURNS trigger AS $func$
BEGIN
    UPDATE public.catalog_units SET
        display      = NEW.display,
        abbreviation = NEW.abbreviation,
        dimension    = NEW.dimension,
        is_default   = NEW.is_default,
        sort_order   = NEW.sort_order,
        updated_at   = now(),
        deleted_at   = NEW.deleted_at
    WHERE id = OLD.id;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_units_update INSTEAD OF UPDATE ON public.inventory_units
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_units_update();

CREATE OR REPLACE FUNCTION private.iv_inventory_units_delete()
RETURNS trigger AS $func$
BEGIN
    UPDATE public.catalog_units SET deleted_at = now(), updated_at = now() WHERE id = OLD.id;
    RETURN OLD;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_units_delete INSTEAD OF DELETE ON public.inventory_units
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_units_delete();

CREATE VIEW public.inventory_tags AS
    SELECT id, company_id, name, warning_threshold, critical_threshold, created_at, updated_at, deleted_at
    FROM public.catalog_tags;

CREATE OR REPLACE FUNCTION private.iv_inventory_tags_insert()
RETURNS trigger AS $func$
BEGIN
    INSERT INTO public.catalog_tags (id, company_id, name, warning_threshold, critical_threshold, created_at, updated_at, deleted_at)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), NEW.company_id, NEW.name,
            NEW.warning_threshold, NEW.critical_threshold,
            COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at);
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_tags_insert INSTEAD OF INSERT ON public.inventory_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_tags_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_tags_update()
RETURNS trigger AS $func$
BEGIN
    UPDATE public.catalog_tags SET
        name               = NEW.name,
        warning_threshold  = NEW.warning_threshold,
        critical_threshold = NEW.critical_threshold,
        updated_at         = now(),
        deleted_at         = NEW.deleted_at
    WHERE id = OLD.id;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_tags_update INSTEAD OF UPDATE ON public.inventory_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_tags_update();

CREATE OR REPLACE FUNCTION private.iv_inventory_tags_delete()
RETURNS trigger AS $func$
BEGIN
    UPDATE public.catalog_tags SET deleted_at = now(), updated_at = now() WHERE id = OLD.id;
    RETURN OLD;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_tags_delete INSTEAD OF DELETE ON public.inventory_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_tags_delete();

CREATE VIEW public.inventory_items AS
    SELECT v.id, v.company_id, ci.name, ci.description,
           v.quantity, v.unit_id, v.sku,
           ci.notes, ci.image_url,
           COALESCE(v.warning_threshold,  ci.default_warning_threshold) AS warning_threshold,
           COALESCE(v.critical_threshold, ci.default_critical_threshold) AS critical_threshold,
           v.created_at, v.updated_at, v.deleted_at
    FROM public.catalog_variants v
    JOIN public.catalog_items ci ON ci.id = v.catalog_item_id;

CREATE OR REPLACE FUNCTION private.iv_inventory_items_insert()
RETURNS trigger AS $func$
DECLARE
    family_id uuid;
BEGIN
    SELECT id INTO family_id FROM public.catalog_items
    WHERE company_id = NEW.company_id AND lower(trim(name)) = lower(trim(NEW.name)) AND deleted_at IS NULL
    LIMIT 1;

    IF family_id IS NULL THEN
        INSERT INTO public.catalog_items (id, company_id, name, description, image_url, default_warning_threshold, default_critical_threshold, default_unit_id, created_at, updated_at, deleted_at)
        VALUES (gen_random_uuid(), NEW.company_id, NEW.name, NEW.description, NEW.image_url,
                NEW.warning_threshold, NEW.critical_threshold, NEW.unit_id,
                COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at)
        RETURNING id INTO family_id;
    END IF;

    INSERT INTO public.catalog_variants (id, company_id, catalog_item_id, sku, quantity, warning_threshold, critical_threshold, unit_id, created_at, updated_at, deleted_at)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), NEW.company_id, family_id, NEW.sku, NEW.quantity, NEW.warning_threshold, NEW.critical_threshold, NEW.unit_id,
            COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at);
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_items_insert INSTEAD OF INSERT ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_items_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_items_update()
RETURNS trigger AS $func$
BEGIN
    UPDATE public.catalog_variants SET
        sku                = NEW.sku,
        quantity           = NEW.quantity,
        warning_threshold  = NEW.warning_threshold,
        critical_threshold = NEW.critical_threshold,
        unit_id            = NEW.unit_id,
        updated_at         = now(),
        deleted_at         = NEW.deleted_at
    WHERE id = OLD.id;

    UPDATE public.catalog_items ci SET
        name        = NEW.name,
        description = NEW.description,
        image_url   = NEW.image_url,
        notes       = NEW.notes,
        updated_at  = now()
    FROM public.catalog_variants v
    WHERE v.id = OLD.id AND ci.id = v.catalog_item_id;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_items_update INSTEAD OF UPDATE ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_items_update();

CREATE OR REPLACE FUNCTION private.iv_inventory_items_delete()
RETURNS trigger AS $func$
BEGIN
    UPDATE public.catalog_variants SET deleted_at = now(), updated_at = now() WHERE id = OLD.id;
    RETURN OLD;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_items_delete INSTEAD OF DELETE ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_items_delete();

CREATE VIEW public.inventory_item_tags AS
    SELECT cit.id, v.id AS item_id, cit.tag_id
    FROM public.catalog_item_tags cit
    JOIN public.catalog_variants v ON v.catalog_item_id = cit.catalog_item_id
    WHERE v.deleted_at IS NULL;

CREATE OR REPLACE FUNCTION private.iv_inventory_item_tags_insert()
RETURNS trigger AS $func$
DECLARE
    family_id uuid;
BEGIN
    SELECT catalog_item_id INTO family_id FROM public.catalog_variants WHERE id = NEW.item_id;
    IF family_id IS NULL THEN
        RAISE EXCEPTION 'inventory_item_tags insert: variant % not found', NEW.item_id;
    END IF;
    INSERT INTO public.catalog_item_tags (id, catalog_item_id, tag_id)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), family_id, NEW.tag_id)
    ON CONFLICT (catalog_item_id, tag_id) DO NOTHING;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_item_tags_insert INSTEAD OF INSERT ON public.inventory_item_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_item_tags_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_item_tags_delete()
RETURNS trigger AS $func$
DECLARE
    family_id uuid;
BEGIN
    SELECT catalog_item_id INTO family_id FROM public.catalog_variants WHERE id = OLD.item_id;
    DELETE FROM public.catalog_item_tags WHERE catalog_item_id = family_id AND tag_id = OLD.tag_id;
    RETURN OLD;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_item_tags_delete INSTEAD OF DELETE ON public.inventory_item_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_item_tags_delete();

CREATE VIEW public.inventory_snapshots AS
    SELECT id, company_id, created_by_id, is_automatic, item_count, notes, created_at
    FROM public.catalog_snapshots;

CREATE VIEW public.inventory_snapshot_items AS
    SELECT id, snapshot_id, original_variant_id AS original_item_id, family_name AS name,
           quantity, unit_display, sku, ''::text AS tags_string, description
    FROM public.catalog_snapshot_items;

CREATE OR REPLACE FUNCTION private.products_mirror_price()
RETURNS trigger AS $func$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.base_price IS NULL OR NEW.base_price = 0 THEN
            NEW.base_price := COALESCE(NEW.default_price, 0);
        ELSIF NEW.default_price IS NULL OR NEW.default_price = 0 THEN
            NEW.default_price := NEW.base_price;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.base_price IS DISTINCT FROM OLD.base_price AND NEW.default_price IS NOT DISTINCT FROM OLD.default_price THEN
            NEW.default_price := NEW.base_price;
        ELSIF NEW.default_price IS DISTINCT FROM OLD.default_price AND NEW.base_price IS NOT DISTINCT FROM OLD.base_price THEN
            NEW.base_price := NEW.default_price;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER trg_products_mirror_price
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION private.products_mirror_price();

COMMIT;
