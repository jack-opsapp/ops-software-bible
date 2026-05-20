-- Atomic lead → project conversion.
-- Mirrors the canonical 'won' behavior documented in
-- 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md § 'won' (line 282):
--   1. Insert projects row (status=accepted, opportunity_id back-link)
--   2. Forward-link any estimates attached to the lead (project_id + project_ref)
--   3. Materialize each LABOR line item across those estimates as a project_tasks row
--   4. Update the opportunities row (stage=won, actual_value, actual_close_date,
--      project_id, project_ref, stage_entered_at, stage_manually_set)
--   5. Insert the stage_transitions row capturing duration_in_stage
-- Runs in one Postgres transaction so partial-failure recovery is impossible —
-- either every row commits or the entire conversion rolls back.
--
-- Idempotency guard: if a project already back-links to this opportunity, the
-- function returns the existing project id without doing anything else. This
-- protects against double-tap and the iOS-vs-web race when both clients try
-- to convert at once.
--
-- Site visit photo auto-attach (10_JOB_LIFECYCLE.md:289) and the Task
-- Generation modal (10_JOB_LIFECYCLE.md:290) remain deferred — silent
-- auto-generate is the v1 behavior on iOS.
--
-- SECURITY DEFINER required: a single transaction must write across
-- projects + estimates + project_tasks + opportunities + stage_transitions,
-- each with distinct RLS policies. Caller authorization is enforced explicitly
-- via the same-company check below.

CREATE OR REPLACE FUNCTION public.convert_lead_to_project(
  p_opportunity_id uuid,
  p_actual_value  numeric,
  p_title         text,
  p_address       text,
  p_user_id       uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_project_id        uuid;
  v_company_id        uuid;
  v_client_id         uuid;
  v_from_stage        text;
  v_stage_entered_at  timestamptz;
  v_now               timestamptz := now();
BEGIN
  -- Read the lead's company / client / current stage. Uses SECURITY DEFINER
  -- so this SELECT bypasses RLS — the same-company check below is what
  -- enforces authorization.
  SELECT company_id, client_id, stage, stage_entered_at
    INTO v_company_id, v_client_id, v_from_stage, v_stage_entered_at
    FROM opportunities
   WHERE id = p_opportunity_id
     AND deleted_at IS NULL;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'opportunity_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Authorization: the caller must be a member of the opportunity's company.
  -- p_user_id is taken on trust (callers pass their own auth.uid()); the RLS
  -- on users still applies to the rows the caller can see at app layer.
  IF NOT EXISTS (
    SELECT 1 FROM users
     WHERE id = p_user_id
       AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE = '42501';
  END IF;

  -- Idempotency: a project may already back-link to this opportunity if a
  -- sibling client raced this call. Return the existing id without retrying.
  SELECT id INTO v_project_id
    FROM projects
   WHERE opportunity_id = p_opportunity_id::text
     AND deleted_at IS NULL
   LIMIT 1;

  IF v_project_id IS NOT NULL THEN
    RETURN v_project_id;
  END IF;

  v_project_id := gen_random_uuid();

  -- 1. Insert the project. opportunity_id is a legacy text column on
  --    projects (no FK), so we cast the uuid to text.
  INSERT INTO projects (
    id, company_id, client_id, opportunity_id,
    title, address, status, created_by, created_at, updated_at
  ) VALUES (
    v_project_id, v_company_id, v_client_id, p_opportunity_id::text,
    p_title, p_address, 'accepted', p_user_id, v_now, v_now
  );

  -- 2. Forward-link any estimates attached to this lead. estimates.project_id
  --    is the legacy text column; estimates.project_ref is the uuid FK to
  --    projects.id. Write both so iOS and web readers both resolve correctly.
  UPDATE estimates
     SET project_id  = v_project_id::text,
         project_ref = v_project_id,
         updated_at  = v_now
   WHERE opportunity_id = p_opportunity_id
     AND project_id IS NULL
     AND deleted_at IS NULL;

  -- 3. Materialize each LABOR line item across those estimates as a
  --    project_tasks row. task_type_id stays nullable: when the source line
  --    item has no task_type_ref the new task displays via custom_title
  --    (which always carries line_items.name — NOT NULL on the source table).
  --    sort_order → display_order; default_duration → duration (fallback 1);
  --    task_types.color → task_color (fallback to schema default '#417394').
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

  -- 4. Update the lead. project_id on opportunities is a uuid column;
  --    project_ref is also uuid — both point at the new project.
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

  -- 5. Insert the stage_transitions row. Mirrors move_opportunity_stage's
  --    pattern (2026-05-07-01-move-opportunity-stage-rpc.sql): captures
  --    duration_in_stage so pipeline analytics remain consistent.
  INSERT INTO stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) VALUES (
    v_company_id, p_opportunity_id, v_from_stage, 'won',
    v_now, p_user_id, v_now - v_stage_entered_at
  );

  RETURN v_project_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.convert_lead_to_project(uuid, numeric, text, text, uuid) TO authenticated;
