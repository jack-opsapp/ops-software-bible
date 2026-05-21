-- 2026-05-21-canpro-catalog-reorg.sql
--
-- Bespoke per-company catalog reorganization for Canpro Deck and Rail
-- (company a612edc0-5c18-4c4d-af97-55b9410dd077). No other company is touched.
--
-- Goal: collapse Canpro's category tree to exactly four top-level categories
-- (Posts, Hardware, Fasteners, Rail) and express every former sub-category as
-- an item-level variation (catalog_options) instead of a category.
--
-- Changes:
--   * Posts      — sub-categories "Side mount" / "Topmount" removed. Corner
--                  inside and Stair Post move up to Posts and gain the
--                  "Mount Type" option every other post already has.
--   * Hardware   — sub-categories "Hardware Level" / "Hardware Stair" and the
--                  empty "Gates" removed. Every hardware item gains a "Type"
--                  option (Normal / Stair). Diverter (was uncategorized)
--                  moves into Hardware.
--   * Fasteners  — "Screws" sub-category removed. The three length items
--                  2" / 3" / 4" merge into one "Leg Screws" item with Length
--                  + Color options. "Teks" is renamed "Tech Screws".
--   * Rail       — items gain a "Type" option (Glass / Picket / Stair).
--                  "Endcap rail" is an accessory and is left typeless.
--   * Corner/Line — the "Hardware Level" mount-type variants are not posts;
--                  they are corner / line sleeves (hardware). They are
--                  extracted into two new Hardware items, "Corner Sleeve"
--                  and "Line Sleeve" (Type = Normal), and the now-unused
--                  "Hardware Level" mount value is dropped from both posts.
--
-- Safety: no catalog_variant is created or deleted. Every variant keeps its
-- id and quantity, so catalog_order_items and catalog_snapshots stay valid;
-- variants are only re-pointed to new parent items and re-linked to new
-- option values. Categories and merged items are removed last, after all
-- items / variants have been re-homed.
--
-- The whole migration is a single DO block: any failure (including the
-- verification asserts at the end) rolls back every change atomically.

DO $$
DECLARE
    v_company       uuid := 'a612edc0-5c18-4c4d-af97-55b9410dd077';

    -- top-level categories (kept)
    v_cat_hardware  uuid := '11111111-1111-0001-1111-000000000010';
    v_cat_posts     uuid := '11111111-1111-0001-1111-000000000020';
    v_cat_rail      uuid := '11111111-1111-0001-1111-000000000040';
    v_cat_fasteners uuid := '11111111-1111-0001-1111-000000000050';

    -- new items
    v_corner_sleeve uuid := gen_random_uuid();
    v_line_sleeve   uuid := gen_random_uuid();
    v_leg_screws    uuid := gen_random_uuid();

    -- scratch / captured option + value ids
    o_id            uuid;
    val_id          uuid;
    cs_black        uuid;
    cs_white        uuid;
    cs_normal       uuid;
    lsv_black       uuid;
    lsv_normal      uuid;
    leg_2           uuid;
    leg_3           uuid;
    leg_4           uuid;
    leg_black       uuid;
    leg_white       uuid;

    -- verification
    pre_variants    int;
    pre_qty         numeric;
    post_variants   int;
    post_qty        numeric;
    n               int;
BEGIN
    SELECT count(*), coalesce(sum(quantity), 0)
      INTO pre_variants, pre_qty
      FROM public.catalog_variants
     WHERE company_id = v_company AND deleted_at IS NULL;

    -- =================================================================
    -- 1. Order the four top-level categories: Posts, Hardware,
    --    Fasteners, Rail.
    -- =================================================================
    UPDATE public.catalog_categories SET sort_order = 10, updated_at = now() WHERE id = v_cat_posts;
    UPDATE public.catalog_categories SET sort_order = 20, updated_at = now() WHERE id = v_cat_hardware;
    UPDATE public.catalog_categories SET sort_order = 30, updated_at = now() WHERE id = v_cat_fasteners;
    UPDATE public.catalog_categories SET sort_order = 40, updated_at = now() WHERE id = v_cat_rail;

    -- =================================================================
    -- 2. Re-home items onto the four top-level categories.
    -- =================================================================
    -- Hardware: 6 ex-"Hardware Level" + 5 ex-"Hardware Stair" + Diverter.
    UPDATE public.catalog_items
       SET category_id = v_cat_hardware, updated_at = now()
     WHERE company_id = v_company
       AND id IN (
           '91aa1454-e51e-b70c-e342-6e2e83e678a1',  -- 45.0
           'accbaeb9-05da-d1aa-7cac-def249c4f8b9',  -- Blank Adapter
           '0d6727bb-c993-caca-16df-5d4502963ea8',  -- Bottom Wall Bracket
           'eba9b67d-992f-1047-e030-ff0d6ff44333',  -- Glass clips
           '272ea97f-ea2d-65b6-4b65-77f96784f0be',  -- Top Wall Bracket
           '6d07ab27-f8a4-9220-a20f-a5ca768c76c6',  -- Windwall Sleeve In
           'cafd6e36-340e-4687-efa2-918e05758f2b',  -- Bottom Down/Up
           '681375bb-e16d-8980-6545-c6cc8b95fab0',  -- End Cap
           '3888b645-67d4-397c-0d9c-d06e13e3ecf4',  -- Stair Post Bracket
           '825fc2f5-efc2-d531-c76a-148cdf07a975',  -- Top Downward
           'cd3946f3-6775-1554-62db-e24fb9352774',  -- Top Upward
           'fc4e178b-566e-4ee8-b7bc-2a0e4ed54d27'   -- Diverter (was uncategorized)
       );

    -- Posts: Corner inside (ex "Side mount") + Stair Post (ex "Topmount").
    UPDATE public.catalog_items
       SET category_id = v_cat_posts, updated_at = now()
     WHERE company_id = v_company
       AND id IN (
           'd47b7f07-b4be-4854-a614-6ba846615712',  -- Corner inside
           '52fc1750-6abb-0209-dbb5-d989ca443e46'   -- Stair Post
       );

    -- Fasteners: rename "Teks" -> "Tech Screws" and move it up.
    UPDATE public.catalog_items
       SET name = 'Tech Screws', category_id = v_cat_fasteners, updated_at = now()
     WHERE company_id = v_company
       AND id = 'e1f57471-9d4f-b30d-7818-2932339801a5';

    -- =================================================================
    -- 3. Hardware items gain a "Type" option (Normal / Stair). The
    --    existing "Color" option (sort 10) is left untouched.
    -- =================================================================
    -- 3a. Create the "Type" option on each pre-existing hardware item.
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    SELECT id, 'Type', 20
      FROM public.catalog_items
     WHERE company_id = v_company
       AND id IN (
           '91aa1454-e51e-b70c-e342-6e2e83e678a1', 'accbaeb9-05da-d1aa-7cac-def249c4f8b9',
           '0d6727bb-c993-caca-16df-5d4502963ea8', 'eba9b67d-992f-1047-e030-ff0d6ff44333',
           '272ea97f-ea2d-65b6-4b65-77f96784f0be', '6d07ab27-f8a4-9220-a20f-a5ca768c76c6',
           'cafd6e36-340e-4687-efa2-918e05758f2b', '681375bb-e16d-8980-6545-c6cc8b95fab0',
           '3888b645-67d4-397c-0d9c-d06e13e3ecf4', '825fc2f5-efc2-d531-c76a-148cdf07a975',
           'cd3946f3-6775-1554-62db-e24fb9352774', 'fc4e178b-566e-4ee8-b7bc-2a0e4ed54d27'
       );

    -- 3b. Value "Normal" for the 6 ex-level items + Diverter.
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    SELECT co.id, 'Normal', 10
      FROM public.catalog_options co
     WHERE co.name = 'Type'
       AND co.catalog_item_id IN (
           '91aa1454-e51e-b70c-e342-6e2e83e678a1', 'accbaeb9-05da-d1aa-7cac-def249c4f8b9',
           '0d6727bb-c993-caca-16df-5d4502963ea8', 'eba9b67d-992f-1047-e030-ff0d6ff44333',
           '272ea97f-ea2d-65b6-4b65-77f96784f0be', '6d07ab27-f8a4-9220-a20f-a5ca768c76c6',
           'fc4e178b-566e-4ee8-b7bc-2a0e4ed54d27'
       );

    -- 3b. Value "Stair" for the 5 ex-stair items.
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    SELECT co.id, 'Stair', 10
      FROM public.catalog_options co
     WHERE co.name = 'Type'
       AND co.catalog_item_id IN (
           'cafd6e36-340e-4687-efa2-918e05758f2b', '681375bb-e16d-8980-6545-c6cc8b95fab0',
           '3888b645-67d4-397c-0d9c-d06e13e3ecf4', '825fc2f5-efc2-d531-c76a-148cdf07a975',
           'cd3946f3-6775-1554-62db-e24fb9352774'
       );

    -- 3c. Link every variant of those 12 items to its item's Type value.
    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
    SELECT cv.id, cov.id
      FROM public.catalog_variants cv
      JOIN public.catalog_options co
        ON co.catalog_item_id = cv.catalog_item_id AND co.name = 'Type'
      JOIN public.catalog_option_values cov
        ON cov.option_id = co.id
     WHERE cv.company_id = v_company
       AND cv.deleted_at IS NULL
       AND cv.catalog_item_id IN (
           '91aa1454-e51e-b70c-e342-6e2e83e678a1', 'accbaeb9-05da-d1aa-7cac-def249c4f8b9',
           '0d6727bb-c993-caca-16df-5d4502963ea8', 'eba9b67d-992f-1047-e030-ff0d6ff44333',
           '272ea97f-ea2d-65b6-4b65-77f96784f0be', '6d07ab27-f8a4-9220-a20f-a5ca768c76c6',
           'cafd6e36-340e-4687-efa2-918e05758f2b', '681375bb-e16d-8980-6545-c6cc8b95fab0',
           '3888b645-67d4-397c-0d9c-d06e13e3ecf4', '825fc2f5-efc2-d531-c76a-148cdf07a975',
           'cd3946f3-6775-1554-62db-e24fb9352774', 'fc4e178b-566e-4ee8-b7bc-2a0e4ed54d27'
       );

    -- =================================================================
    -- 4. Rail items gain a "Type" option (Glass / Picket / Stair).
    --    "Endcap rail" is an accessory and is intentionally left typeless.
    -- =================================================================
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    SELECT id, 'Type', 20
      FROM public.catalog_items
     WHERE company_id = v_company
       AND id IN (
           '860dc363-f02d-69ae-b31d-87b5b20f644d',  -- Glass Rail 12'
           '44e50137-c2a8-9fc9-1a7c-4807000ee5e8',  -- Glass Rail 19'6
           'd60292d1-bc78-79a8-6958-5b5716774ca3',  -- Picket Rail 19'6
           'd8a17ad9-e424-aa52-5d8e-19b7bd4b198e'   -- Picket Stair
       );

    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    SELECT co.id, 'Glass', 10
      FROM public.catalog_options co
     WHERE co.name = 'Type'
       AND co.catalog_item_id IN (
           '860dc363-f02d-69ae-b31d-87b5b20f644d',
           '44e50137-c2a8-9fc9-1a7c-4807000ee5e8'
       );

    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    SELECT co.id, 'Picket', 10
      FROM public.catalog_options co
     WHERE co.name = 'Type'
       AND co.catalog_item_id = 'd60292d1-bc78-79a8-6958-5b5716774ca3';

    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    SELECT co.id, 'Stair', 10
      FROM public.catalog_options co
     WHERE co.name = 'Type'
       AND co.catalog_item_id = 'd8a17ad9-e424-aa52-5d8e-19b7bd4b198e';

    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
    SELECT cv.id, cov.id
      FROM public.catalog_variants cv
      JOIN public.catalog_options co
        ON co.catalog_item_id = cv.catalog_item_id AND co.name = 'Type'
      JOIN public.catalog_option_values cov
        ON cov.option_id = co.id
     WHERE cv.company_id = v_company
       AND cv.deleted_at IS NULL
       AND cv.catalog_item_id IN (
           '860dc363-f02d-69ae-b31d-87b5b20f644d',
           '44e50137-c2a8-9fc9-1a7c-4807000ee5e8',
           'd60292d1-bc78-79a8-6958-5b5716774ca3',
           'd8a17ad9-e424-aa52-5d8e-19b7bd4b198e'
       );

    -- =================================================================
    -- 5. Posts: Corner inside and Stair Post gain the "Mount Type"
    --    option every other post already carries.
    -- =================================================================
    -- Corner inside -> Mount Type "Side mount".
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES ('d47b7f07-b4be-4854-a614-6ba846615712', 'Mount Type', 20)
    RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Side mount', 20)
    RETURNING id INTO val_id;
    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
    SELECT cv.id, val_id
      FROM public.catalog_variants cv
     WHERE cv.catalog_item_id = 'd47b7f07-b4be-4854-a614-6ba846615712'
       AND cv.deleted_at IS NULL;

    -- Stair Post -> Mount Type "Topmount".
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES ('52fc1750-6abb-0209-dbb5-d989ca443e46', 'Mount Type', 20)
    RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Topmount', 10)
    RETURNING id INTO val_id;
    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
    SELECT cv.id, val_id
      FROM public.catalog_variants cv
     WHERE cv.catalog_item_id = '52fc1750-6abb-0209-dbb5-d989ca443e46'
       AND cv.deleted_at IS NULL;

    -- =================================================================
    -- 6. Extract corner / line sleeves out of the Corner and Line posts.
    --    The "Hardware Level" mount variants are hardware sleeves, not
    --    posts: re-point them onto two new Hardware items.
    -- =================================================================
    INSERT INTO public.catalog_items (id, company_id, category_id, name, is_active, created_at, updated_at)
    VALUES
      (v_corner_sleeve, v_company, v_cat_hardware, 'Corner Sleeve', true, now(), now()),
      (v_line_sleeve,   v_company, v_cat_hardware, 'Line Sleeve',   true, now(), now());

    -- 6a. Corner Sleeve options: Color (Black/White) + Type (Normal).
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES (v_corner_sleeve, 'Color', 10) RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Black', 10) RETURNING id INTO cs_black;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'White', 20) RETURNING id INTO cs_white;
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES (v_corner_sleeve, 'Type', 20) RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Normal', 10) RETURNING id INTO cs_normal;

    -- 6b. Re-point the two Corner "Hardware Level" variants.
    DELETE FROM public.catalog_variant_option_values
     WHERE variant_id IN (
        '22f9a4ac-eb8d-46a7-a134-1cc75800a700',   -- Corner / Black / Hardware Level (qty 216)
        '2c7cdf44-3473-499b-b086-73737505a565');  -- Corner / White / Hardware Level (qty 300)
    UPDATE public.catalog_variants
       SET catalog_item_id = v_corner_sleeve, updated_at = now()
     WHERE id IN (
        '22f9a4ac-eb8d-46a7-a134-1cc75800a700',
        '2c7cdf44-3473-499b-b086-73737505a565');
    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id) VALUES
      ('22f9a4ac-eb8d-46a7-a134-1cc75800a700', cs_black),
      ('22f9a4ac-eb8d-46a7-a134-1cc75800a700', cs_normal),
      ('2c7cdf44-3473-499b-b086-73737505a565', cs_white),
      ('2c7cdf44-3473-499b-b086-73737505a565', cs_normal);

    -- 6c. Line Sleeve options: Color (Black) + Type (Normal).
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES (v_line_sleeve, 'Color', 10) RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Black', 10) RETURNING id INTO lsv_black;
    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES (v_line_sleeve, 'Type', 20) RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Normal', 10) RETURNING id INTO lsv_normal;

    -- 6d. Re-point the Line "Hardware Level" variant.
    DELETE FROM public.catalog_variant_option_values
     WHERE variant_id = '5692fb99-f1bd-45af-bf6c-ff6128b1d96b';  -- Line / Black / Hardware Level (qty 220)
    UPDATE public.catalog_variants
       SET catalog_item_id = v_line_sleeve, updated_at = now()
     WHERE id = '5692fb99-f1bd-45af-bf6c-ff6128b1d96b';
    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id) VALUES
      ('5692fb99-f1bd-45af-bf6c-ff6128b1d96b', lsv_black),
      ('5692fb99-f1bd-45af-bf6c-ff6128b1d96b', lsv_normal);

    -- 6e. The "Hardware Level" mount value is now unused on both posts: drop it.
    --     The Corner / Line "Mount Type" option keeps Topmount + Side mount.
    DELETE FROM public.catalog_option_values
     WHERE id IN (
        'bacbb1a8-97f8-b3db-5da8-d45aae1b2889',   -- Corner / Mount Type / Hardware Level
        'ffa79b01-d3fd-5d2d-03ab-b80a784417ac');  -- Line / Mount Type / Hardware Level

    -- =================================================================
    -- 7. Fasteners: merge the three length items 2" / 3" / 4" into one
    --    "Leg Screws" item with Length + Color options.
    -- =================================================================
    INSERT INTO public.catalog_items (id, company_id, category_id, name, is_active, created_at, updated_at)
    VALUES (v_leg_screws, v_company, v_cat_fasteners, 'Leg Screws', true, now(), now());

    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES (v_leg_screws, 'Length', 10) RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, '2"', 10) RETURNING id INTO leg_2;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, '3"', 20) RETURNING id INTO leg_3;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, '4"', 30) RETURNING id INTO leg_4;

    INSERT INTO public.catalog_options (catalog_item_id, name, sort_order)
    VALUES (v_leg_screws, 'Color', 20) RETURNING id INTO o_id;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'Black', 10) RETURNING id INTO leg_black;
    INSERT INTO public.catalog_option_values (option_id, value, sort_order)
    VALUES (o_id, 'White', 20) RETURNING id INTO leg_white;

    -- Re-point the five existing length/colour variants onto Leg Screws.
    DELETE FROM public.catalog_variant_option_values
     WHERE variant_id IN (
        '0595ba30-de12-4427-8ef0-da5d8a8a645e',   -- 2" Black
        '220769ee-4db2-4da4-8063-60ebfe9a9818',   -- 2" White
        '5029005b-587d-49b3-91cd-4699cec61ab0',   -- 3" Black
        '5b5a7019-91fe-4246-ac83-5aee6af489bc',   -- 3" White
        'd2acba84-f2ff-4e8b-943d-64939da00d53');  -- 4" Black
    UPDATE public.catalog_variants
       SET catalog_item_id = v_leg_screws, updated_at = now()
     WHERE id IN (
        '0595ba30-de12-4427-8ef0-da5d8a8a645e',
        '220769ee-4db2-4da4-8063-60ebfe9a9818',
        '5029005b-587d-49b3-91cd-4699cec61ab0',
        '5b5a7019-91fe-4246-ac83-5aee6af489bc',
        'd2acba84-f2ff-4e8b-943d-64939da00d53');
    INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id) VALUES
      ('0595ba30-de12-4427-8ef0-da5d8a8a645e', leg_2), ('0595ba30-de12-4427-8ef0-da5d8a8a645e', leg_black),
      ('220769ee-4db2-4da4-8063-60ebfe9a9818', leg_2), ('220769ee-4db2-4da4-8063-60ebfe9a9818', leg_white),
      ('5029005b-587d-49b3-91cd-4699cec61ab0', leg_3), ('5029005b-587d-49b3-91cd-4699cec61ab0', leg_black),
      ('5b5a7019-91fe-4246-ac83-5aee6af489bc', leg_3), ('5b5a7019-91fe-4246-ac83-5aee6af489bc', leg_white),
      ('d2acba84-f2ff-4e8b-943d-64939da00d53', leg_4), ('d2acba84-f2ff-4e8b-943d-64939da00d53', leg_black);

    -- The three old length items are now empty; remove them. Their options
    -- and option values cascade-delete; their variants have already moved.
    DELETE FROM public.catalog_items
     WHERE company_id = v_company
       AND id IN (
        '79edf654-ee4b-cc82-c2ef-3473223b25ca',   -- 2"
        'd42f6efb-2903-16db-f85d-8b7578d9fab3',   -- 3"
        '5dc57b52-7885-0313-fae0-4ddd42c7be08');  -- 4"

    -- =================================================================
    -- 8. Soft-delete the six former sub-categories. All their items have
    --    been re-homed above; "Gates" was already empty.
    -- =================================================================
    UPDATE public.catalog_categories
       SET deleted_at = now(), updated_at = now()
     WHERE company_id = v_company
       AND deleted_at IS NULL
       AND id IN (
        '11111111-1111-0001-1111-000000000011',   -- Hardware Level
        '11111111-1111-0001-1111-000000000012',   -- Hardware Stair
        '11111111-1111-0001-1111-000000000060',   -- Gates
        '11111111-1111-0001-1111-000000000030',   -- Side mount
        '11111111-1111-0001-1111-000000000031',   -- Topmount
        '11111111-1111-0001-1111-000000000051');  -- Screws

    -- =================================================================
    -- 9. Verification — abort the whole transaction on any drift.
    -- =================================================================
    SELECT count(*), coalesce(sum(quantity), 0)
      INTO post_variants, post_qty
      FROM public.catalog_variants
     WHERE company_id = v_company AND deleted_at IS NULL;

    IF post_variants <> pre_variants THEN
        RAISE EXCEPTION 'Variant count drift: pre=%, post=%', pre_variants, post_variants;
    END IF;
    IF post_qty <> pre_qty THEN
        RAISE EXCEPTION 'Total quantity drift: pre=%, post=%', pre_qty, post_qty;
    END IF;

    SELECT count(*) INTO n
      FROM public.catalog_categories
     WHERE company_id = v_company AND deleted_at IS NULL;
    IF n <> 4 THEN
        RAISE EXCEPTION 'Expected 4 active categories, found %', n;
    END IF;

    SELECT count(*) INTO n
      FROM public.catalog_categories
     WHERE company_id = v_company AND deleted_at IS NULL AND parent_id IS NOT NULL;
    IF n <> 0 THEN
        RAISE EXCEPTION 'Expected 0 sub-categories, found %', n;
    END IF;

    SELECT count(*) INTO n
      FROM public.catalog_items
     WHERE company_id = v_company AND deleted_at IS NULL AND category_id IS NULL;
    IF n <> 0 THEN
        RAISE EXCEPTION 'Found % uncategorized items', n;
    END IF;

    SELECT count(*) INTO n FROM public.catalog_items
     WHERE company_id = v_company AND deleted_at IS NULL AND category_id = v_cat_posts;
    IF n <> 7 THEN RAISE EXCEPTION 'Posts: expected 7 items, found %', n; END IF;

    SELECT count(*) INTO n FROM public.catalog_items
     WHERE company_id = v_company AND deleted_at IS NULL AND category_id = v_cat_hardware;
    IF n <> 14 THEN RAISE EXCEPTION 'Hardware: expected 14 items, found %', n; END IF;

    SELECT count(*) INTO n FROM public.catalog_items
     WHERE company_id = v_company AND deleted_at IS NULL AND category_id = v_cat_fasteners;
    IF n <> 2 THEN RAISE EXCEPTION 'Fasteners: expected 2 items, found %', n; END IF;

    SELECT count(*) INTO n FROM public.catalog_items
     WHERE company_id = v_company AND deleted_at IS NULL AND category_id = v_cat_rail;
    IF n <> 5 THEN RAISE EXCEPTION 'Rail: expected 5 items, found %', n; END IF;

    RAISE NOTICE 'Canpro catalog reorg OK: % variants, total qty %, items Posts/7 Hardware/14 Fasteners/2 Rail/5',
        post_variants, post_qty;
END $$;
