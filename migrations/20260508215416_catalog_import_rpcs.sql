CREATE OR REPLACE FUNCTION public.catalog_import_validate(
  p_company_id uuid,
  p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_caller_company_id uuid;
  v_errors jsonb := '[]'::jsonb;
  v_families jsonb;
  v_variants jsonb;
  v_family jsonb;
  v_variant jsonb;
  v_seen_family_indexes jsonb := '{}'::jsonb;
  v_seen_variant_indexes jsonb := '{}'::jsonb;
  v_row_index int;
  v_family_row_index int;
  v_name text;
  v_sku text;
  v_category_id uuid;
  v_unit_id uuid;
  v_quantity numeric;
  v_default_price numeric;
  v_default_unit_cost numeric;
  v_threshold numeric;
BEGIN
  v_caller_company_id := private.get_user_company_id();
  IF v_caller_company_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'errors', jsonb_build_array(jsonb_build_object('scope','payload','row_index',-1,'field','auth','reason','No authenticated company context.')));
  END IF;
  IF v_caller_company_id <> p_company_id THEN
    RETURN jsonb_build_object('success', false, 'errors', jsonb_build_array(jsonb_build_object('scope','payload','row_index',-1,'field','company_id','reason','p_company_id does not match the caller''s company.')));
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'errors', jsonb_build_array(jsonb_build_object('scope','payload','row_index',-1,'field','root','reason','Payload must be a JSON object.')));
  END IF;

  v_families := COALESCE(p_payload->'families', '[]'::jsonb);
  v_variants := COALESCE(p_payload->'variants', '[]'::jsonb);

  IF jsonb_typeof(v_families) <> 'array' THEN
    v_errors := v_errors || jsonb_build_object('scope','payload','row_index',-1,'field','families','reason','families must be a JSON array.');
  END IF;
  IF jsonb_typeof(v_variants) <> 'array' THEN
    v_errors := v_errors || jsonb_build_object('scope','payload','row_index',-1,'field','variants','reason','variants must be a JSON array.');
  END IF;
  IF jsonb_array_length(v_families) = 0 THEN
    v_errors := v_errors || jsonb_build_object('scope','payload','row_index',-1,'field','families','reason','At least one family row is required.');
  END IF;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  FOR v_family IN SELECT * FROM jsonb_array_elements(v_families) LOOP
    IF jsonb_typeof(v_family->'row_index') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object('scope','family','row_index',-1,'field','row_index','reason','row_index must be present and numeric.');
      CONTINUE;
    END IF;
    v_row_index := (v_family->>'row_index')::int;
    IF v_seen_family_indexes ? v_row_index::text THEN
      v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','row_index','reason','Duplicate row_index in families.');
    ELSE
      v_seen_family_indexes := v_seen_family_indexes || jsonb_build_object(v_row_index::text, true);
    END IF;

    v_name := NULLIF(TRIM(COALESCE(v_family->>'name','')),'');
    IF v_name IS NULL THEN
      v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','name','reason','name is required and cannot be blank.');
    END IF;

    IF v_family ? 'category_id' AND jsonb_typeof(v_family->'category_id') <> 'null' THEN
      BEGIN
        v_category_id := (v_family->>'category_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM catalog_categories WHERE id = v_category_id AND company_id = p_company_id AND deleted_at IS NULL) THEN
          v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','category_id','reason','category_id does not match an active category for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','category_id','reason','category_id is not a valid uuid.');
      END;
    END IF;

    IF v_family ? 'default_unit_id' AND jsonb_typeof(v_family->'default_unit_id') <> 'null' THEN
      BEGIN
        v_unit_id := (v_family->>'default_unit_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM catalog_units WHERE id = v_unit_id AND company_id = p_company_id AND deleted_at IS NULL) THEN
          v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','default_unit_id','reason','default_unit_id does not match an active unit for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','default_unit_id','reason','default_unit_id is not a valid uuid.');
      END;
    END IF;

    FOR v_threshold IN
      SELECT (v_family->>k)::numeric
      FROM unnest(ARRAY['default_price','default_unit_cost','default_warning_threshold','default_critical_threshold']) k
      WHERE v_family ? k AND jsonb_typeof(v_family->k) = 'number'
    LOOP
      IF v_threshold < 0 THEN
        v_errors := v_errors || jsonb_build_object('scope','family','row_index',v_row_index,'field','numeric','reason','Numeric values must be >= 0.');
      END IF;
    END LOOP;
  END LOOP;

  FOR v_variant IN SELECT * FROM jsonb_array_elements(v_variants) LOOP
    IF jsonb_typeof(v_variant->'row_index') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object('scope','variant','row_index',-1,'field','row_index','reason','row_index must be present and numeric.');
      CONTINUE;
    END IF;
    v_row_index := (v_variant->>'row_index')::int;
    IF v_seen_variant_indexes ? v_row_index::text THEN
      v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','row_index','reason','Duplicate row_index in variants.');
    ELSE
      v_seen_variant_indexes := v_seen_variant_indexes || jsonb_build_object(v_row_index::text, true);
    END IF;

    IF jsonb_typeof(v_variant->'family_row_index') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','family_row_index','reason','family_row_index must be present and numeric.');
    ELSE
      v_family_row_index := (v_variant->>'family_row_index')::int;
      IF NOT (v_seen_family_indexes ? v_family_row_index::text) THEN
        v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','family_row_index','reason','family_row_index does not reference a family in this payload.');
      END IF;
    END IF;

    IF jsonb_typeof(v_variant->'quantity') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','quantity','reason','quantity is required and must be numeric.');
    ELSE
      v_quantity := (v_variant->>'quantity')::numeric;
      IF v_quantity < 0 THEN
        v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','quantity','reason','quantity must be >= 0.');
      END IF;
    END IF;

    FOR v_threshold IN
      SELECT (v_variant->>k)::numeric
      FROM unnest(ARRAY['price_override','unit_cost_override','warning_threshold','critical_threshold']) k
      WHERE v_variant ? k AND jsonb_typeof(v_variant->k) = 'number'
    LOOP
      IF v_threshold < 0 THEN
        v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','numeric','reason','Numeric values must be >= 0.');
      END IF;
    END LOOP;

    IF v_variant ? 'unit_id' AND jsonb_typeof(v_variant->'unit_id') <> 'null' THEN
      BEGIN
        v_unit_id := (v_variant->>'unit_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM catalog_units WHERE id = v_unit_id AND company_id = p_company_id AND deleted_at IS NULL) THEN
          v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','unit_id','reason','unit_id does not match an active unit for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','unit_id','reason','unit_id is not a valid uuid.');
      END;
    END IF;

    v_sku := NULLIF(TRIM(COALESCE(v_variant->>'sku','')),'');
    IF v_sku IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM catalog_variants WHERE company_id = p_company_id AND deleted_at IS NULL AND sku IS NOT NULL AND LOWER(TRIM(sku)) = LOWER(v_sku)) THEN
        v_errors := v_errors || jsonb_build_object('scope','variant','row_index',v_row_index,'field','sku','reason','sku already exists for an active variant in this company.');
      END IF;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  RETURN jsonb_build_object('success', true, 'totals', jsonb_build_object('families', jsonb_array_length(v_families), 'variants', jsonb_array_length(v_variants)));
END;
$$;

REVOKE ALL ON FUNCTION public.catalog_import_validate(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.catalog_import_validate(uuid, jsonb) TO authenticated;


CREATE OR REPLACE FUNCTION public.catalog_import_apply(
  p_company_id uuid,
  p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_validation jsonb;
  v_family jsonb;
  v_variant jsonb;
  v_family_id_map jsonb := '{}'::jsonb;
  v_variant_id_map jsonb := '{}'::jsonb;
  v_row_index int;
  v_family_row_index int;
  v_new_family_id uuid;
  v_new_variant_id uuid;
  v_target_family_id uuid;
  v_families jsonb;
  v_variants jsonb;
BEGIN
  v_validation := public.catalog_import_validate(p_company_id, p_payload);
  IF NOT (v_validation->>'success')::boolean THEN
    RETURN v_validation;
  END IF;

  v_families := COALESCE(p_payload->'families', '[]'::jsonb);
  v_variants := COALESCE(p_payload->'variants', '[]'::jsonb);

  FOR v_family IN SELECT * FROM jsonb_array_elements(v_families) LOOP
    v_row_index := (v_family->>'row_index')::int;

    INSERT INTO catalog_items (
      company_id, category_id, name, description,
      default_price, default_unit_cost,
      default_warning_threshold, default_critical_threshold,
      default_unit_id, is_active
    ) VALUES (
      p_company_id,
      NULLIF(v_family->>'category_id','')::uuid,
      TRIM(v_family->>'name'),
      NULLIF(v_family->>'description',''),
      NULLIF(v_family->>'default_price','')::numeric,
      NULLIF(v_family->>'default_unit_cost','')::numeric,
      NULLIF(v_family->>'default_warning_threshold','')::double precision,
      NULLIF(v_family->>'default_critical_threshold','')::double precision,
      NULLIF(v_family->>'default_unit_id','')::uuid,
      true
    ) RETURNING id INTO v_new_family_id;

    v_family_id_map := v_family_id_map || jsonb_build_object(v_row_index::text, v_new_family_id);
  END LOOP;

  FOR v_variant IN SELECT * FROM jsonb_array_elements(v_variants) LOOP
    v_row_index := (v_variant->>'row_index')::int;
    v_family_row_index := (v_variant->>'family_row_index')::int;
    v_target_family_id := (v_family_id_map->>v_family_row_index::text)::uuid;

    INSERT INTO catalog_variants (
      company_id, catalog_item_id, sku, quantity,
      price_override, unit_cost_override,
      warning_threshold, critical_threshold,
      unit_id, is_active
    ) VALUES (
      p_company_id,
      v_target_family_id,
      NULLIF(TRIM(v_variant->>'sku'),''),
      COALESCE((v_variant->>'quantity')::double precision, 0),
      NULLIF(v_variant->>'price_override','')::numeric,
      NULLIF(v_variant->>'unit_cost_override','')::numeric,
      NULLIF(v_variant->>'warning_threshold','')::double precision,
      NULLIF(v_variant->>'critical_threshold','')::double precision,
      NULLIF(v_variant->>'unit_id','')::uuid,
      true
    ) RETURNING id INTO v_new_variant_id;

    v_variant_id_map := v_variant_id_map || jsonb_build_object(v_row_index::text, v_new_variant_id);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'created_family_ids', v_family_id_map,
    'created_variant_ids', v_variant_id_map,
    'totals', jsonb_build_object('families', jsonb_array_length(v_families), 'variants', jsonb_array_length(v_variants))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.catalog_import_apply(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.catalog_import_apply(uuid, jsonb) TO authenticated;
