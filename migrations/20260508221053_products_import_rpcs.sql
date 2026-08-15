CREATE OR REPLACE FUNCTION public.products_import_validate(
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
  v_products jsonb;
  v_product jsonb;
  v_seen_indexes jsonb := '{}'::jsonb;
  v_row_index int;
  v_name text;
  v_kind text;
  v_type text;
  v_category_id uuid;
  v_unit_id uuid;
  v_base_price numeric;
  v_unit_cost numeric;
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

  v_products := COALESCE(p_payload->'products', '[]'::jsonb);

  IF jsonb_typeof(v_products) <> 'array' THEN
    v_errors := v_errors || jsonb_build_object('scope','payload','row_index',-1,'field','products','reason','products must be a JSON array.');
  END IF;
  IF jsonb_typeof(v_products) = 'array' AND jsonb_array_length(v_products) = 0 THEN
    v_errors := v_errors || jsonb_build_object('scope','payload','row_index',-1,'field','products','reason','At least one product row is required.');
  END IF;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  FOR v_product IN SELECT * FROM jsonb_array_elements(v_products) LOOP
    IF jsonb_typeof(v_product->'row_index') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object('scope','product','row_index',-1,'field','row_index','reason','row_index must be present and numeric.');
      CONTINUE;
    END IF;
    v_row_index := (v_product->>'row_index')::int;
    IF v_seen_indexes ? v_row_index::text THEN
      v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','row_index','reason','Duplicate row_index in products.');
    ELSE
      v_seen_indexes := v_seen_indexes || jsonb_build_object(v_row_index::text, true);
    END IF;

    v_name := NULLIF(TRIM(COALESCE(v_product->>'name','')),'');
    IF v_name IS NULL THEN
      v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','name','reason','name is required and cannot be blank.');
    END IF;

    IF jsonb_typeof(v_product->'base_price') <> 'number' THEN
      v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','base_price','reason','base_price is required and must be numeric.');
    ELSE
      v_base_price := (v_product->>'base_price')::numeric;
      IF v_base_price < 0 THEN
        v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','base_price','reason','base_price must be >= 0.');
      END IF;
    END IF;

    IF v_product ? 'unit_cost' AND jsonb_typeof(v_product->'unit_cost') = 'number' THEN
      v_unit_cost := (v_product->>'unit_cost')::numeric;
      IF v_unit_cost < 0 THEN
        v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','unit_cost','reason','unit_cost must be >= 0.');
      END IF;
    ELSIF v_product ? 'unit_cost' AND jsonb_typeof(v_product->'unit_cost') NOT IN ('null','number') THEN
      v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','unit_cost','reason','unit_cost must be numeric or null.');
    END IF;

    IF v_product ? 'category_id' AND jsonb_typeof(v_product->'category_id') <> 'null' THEN
      BEGIN
        v_category_id := (v_product->>'category_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM catalog_categories WHERE id = v_category_id AND company_id = p_company_id AND deleted_at IS NULL) THEN
          v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','category_id','reason','category_id does not match an active category for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','category_id','reason','category_id is not a valid uuid.');
      END;
    END IF;

    IF v_product ? 'unit_id' AND jsonb_typeof(v_product->'unit_id') <> 'null' THEN
      BEGIN
        v_unit_id := (v_product->>'unit_id')::uuid;
        IF NOT EXISTS (SELECT 1 FROM catalog_units WHERE id = v_unit_id AND company_id = p_company_id AND deleted_at IS NULL) THEN
          v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','unit_id','reason','unit_id does not match an active unit for this company.');
        END IF;
      EXCEPTION WHEN invalid_text_representation THEN
        v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','unit_id','reason','unit_id is not a valid uuid.');
      END;
    END IF;

    IF v_product ? 'kind' AND jsonb_typeof(v_product->'kind') <> 'null' THEN
      v_kind := v_product->>'kind';
      IF v_kind NOT IN ('service','good') THEN
        v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','kind','reason','kind must be ''service'' or ''good''.');
      END IF;
    END IF;

    IF v_product ? 'type' AND jsonb_typeof(v_product->'type') <> 'null' THEN
      v_type := v_product->>'type';
      IF v_type NOT IN ('LABOR','MATERIAL','OTHER') THEN
        v_errors := v_errors || jsonb_build_object('scope','product','row_index',v_row_index,'field','type','reason','type must be ''LABOR'', ''MATERIAL'', or ''OTHER''.');
      END IF;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN jsonb_build_object('success', false, 'errors', v_errors);
  END IF;

  RETURN jsonb_build_object('success', true, 'totals', jsonb_build_object('products', jsonb_array_length(v_products)));
END;
$$;

REVOKE ALL ON FUNCTION public.products_import_validate(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.products_import_validate(uuid, jsonb) TO authenticated;


CREATE OR REPLACE FUNCTION public.products_import_apply(
  p_company_id uuid,
  p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_validation jsonb;
  v_product jsonb;
  v_product_id_map jsonb := '{}'::jsonb;
  v_row_index int;
  v_new_product_id uuid;
  v_products jsonb;
BEGIN
  v_validation := public.products_import_validate(p_company_id, p_payload);
  IF NOT (v_validation->>'success')::boolean THEN
    RETURN v_validation;
  END IF;

  v_products := COALESCE(p_payload->'products', '[]'::jsonb);

  FOR v_product IN SELECT * FROM jsonb_array_elements(v_products) LOOP
    v_row_index := (v_product->>'row_index')::int;

    INSERT INTO products (
      company_id, name, description, base_price, unit_cost,
      unit, category, category_id, unit_id, pricing_unit,
      sku, kind, type, is_taxable, is_active
    ) VALUES (
      p_company_id,
      TRIM(v_product->>'name'),
      NULLIF(v_product->>'description',''),
      (v_product->>'base_price')::numeric,
      NULLIF(v_product->>'unit_cost','')::numeric,
      NULLIF(v_product->>'unit',''),
      NULLIF(v_product->>'category',''),
      NULLIF(v_product->>'category_id','')::uuid,
      NULLIF(v_product->>'unit_id','')::uuid,
      COALESCE(NULLIF(v_product->>'pricing_unit',''), 'each'),
      NULLIF(v_product->>'sku',''),
      COALESCE(NULLIF(v_product->>'kind',''), 'service'),
      COALESCE(NULLIF(v_product->>'type',''), 'LABOR'),
      COALESCE((v_product->>'is_taxable')::boolean, true),
      true
    ) RETURNING id INTO v_new_product_id;

    v_product_id_map := v_product_id_map || jsonb_build_object(v_row_index::text, v_new_product_id);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'created_product_ids', v_product_id_map,
    'totals', jsonb_build_object('products', jsonb_array_length(v_products))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.products_import_apply(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.products_import_apply(uuid, jsonb) TO authenticated;
