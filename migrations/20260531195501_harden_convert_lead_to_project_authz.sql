CREATE OR REPLACE FUNCTION public.convert_lead_to_project(
  p_opportunity_id uuid,
  p_actual_value   numeric,
  p_title          text,
  p_address        text,
  p_user_id        uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_project_id        uuid;
  v_company_id        uuid;
  v_client_id         uuid;
  v_from_stage        text;
  v_stage_entered_at  timestamptz;
  v_actor_company     uuid;
  v_now               timestamptz := now();
BEGIN
  SELECT company_id, client_id, stage, stage_entered_at
    INTO v_company_id, v_client_id, v_from_stage, v_stage_entered_at
    FROM opportunities
   WHERE id = p_opportunity_id
     AND deleted_at IS NULL;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'opportunity_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Authorize the CALLER, not the client-supplied p_user_id. Actor company is
  -- derived from the JWT email claim via the same SECURITY DEFINER helper that
  -- backs company_isolation RLS. anon/no-JWT -> NULL (rejected); cross-company
  -- rejected. (leads-review C-6/C-12)
  v_actor_company := private.get_user_company_id();
  IF v_actor_company IS NULL OR v_actor_company <> v_company_id THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT private.current_user_has_permission('pipeline.manage', 'all') THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM users
     WHERE id = p_user_id
       AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_project_id
    FROM projects
   WHERE opportunity_id = p_opportunity_id::text
     AND deleted_at IS NULL
   LIMIT 1;

  IF v_project_id IS NOT NULL THEN
    RETURN v_project_id;
  END IF;

  v_project_id := gen_random_uuid();

  INSERT INTO projects (
    id, company_id, client_id, opportunity_id,
    title, address, status, created_by, created_at, updated_at
  ) VALUES (
    v_project_id, v_company_id, v_client_id, p_opportunity_id::text,
    p_title, p_address, 'accepted', p_user_id, v_now, v_now
  );

  UPDATE estimates
     SET project_id  = v_project_id::text,
         project_ref = v_project_id,
         updated_at  = v_now
   WHERE opportunity_id = p_opportunity_id
     AND project_id IS NULL
     AND deleted_at IS NULL;

  INSERT INTO project_tasks (
    id, company_id, project_id, task_type_id,
    custom_title, source_line_item_id, source_estimate_id,
    status, display_order, duration, task_color, created_at, updated_at
  )
  SELECT
    gen_random_uuid(),
    v_company_id,
    v_project_id,
    li.task_type_ref,
    li.name,
    li.id::text,
    li.estimate_id::text,
    'active',
    COALESCE(li.sort_order, 0),
    COALESCE(tt.default_duration, 1),
    COALESCE(tt.color, '#417394'),
    v_now,
    v_now
  FROM line_items li
  LEFT JOIN task_types tt ON tt.id = li.task_type_ref
  WHERE li.estimate_id IN (
          SELECT id FROM estimates
           WHERE opportunity_id = p_opportunity_id
             AND deleted_at IS NULL
        )
    AND li.type = 'LABOR';

  INSERT INTO project_photos (
    id, project_id, company_id, url, source,
    site_visit_id, uploaded_by, taken_at, created_at
  )
  SELECT
    gen_random_uuid(),
    v_project_id::text,
    v_company_id::text,
    photo_url,
    'site_visit',
    sv.id,
    sv.created_by,
    NULL,
    v_now
  FROM site_visits sv
  CROSS JOIN LATERAL unnest(sv.photos) AS photo_url
  WHERE sv.opportunity_id = p_opportunity_id
    AND sv.deleted_at IS NULL
    AND photo_url IS NOT NULL
    AND photo_url <> '';

  UPDATE opportunities
     SET stage              = 'won',
         stage_entered_at   = v_now,
         stage_manually_set = true,
         actual_value       = p_actual_value,
         actual_close_date  = v_now::date,
         project_id         = v_project_id,
         project_ref        = v_project_id,
         updated_at         = v_now
   WHERE id = p_opportunity_id;

  INSERT INTO stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) VALUES (
    v_company_id, p_opportunity_id, v_from_stage, 'won',
    v_now, p_user_id, v_now - v_stage_entered_at
  );

  RETURN v_project_id;
END;
$function$;
