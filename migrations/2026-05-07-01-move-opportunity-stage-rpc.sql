-- Atomic stage move for pipeline opportunities.
-- Updates stage / stage_entered_at / stage_manually_set on opportunities,
-- AND inserts a stage_transitions row capturing duration_in_stage.
-- Returns the updated opportunity row.

CREATE OR REPLACE FUNCTION public.move_opportunity_stage(
  p_opportunity_id uuid,
  p_to_stage text,
  p_user_id uuid
)
RETURNS opportunities
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_from_stage text;
  v_prior_entered_at timestamptz;
  v_now timestamptz := now();
  v_updated opportunities;
BEGIN
  -- Read current state. RLS will reject if caller can't see this row.
  SELECT company_id, stage, stage_entered_at
    INTO v_company_id, v_from_stage, v_prior_entered_at
    FROM opportunities
   WHERE id = p_opportunity_id
     AND deleted_at IS NULL;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'opportunity_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- No-op if already in the target stage; still return the row.
  IF v_from_stage = p_to_stage THEN
    SELECT * INTO v_updated FROM opportunities WHERE id = p_opportunity_id;
    RETURN v_updated;
  END IF;

  -- Update opportunity: stage + stage_entered_at + manually_set flag.
  UPDATE opportunities
     SET stage              = p_to_stage,
         stage_entered_at   = v_now,
         stage_manually_set = true,
         updated_at         = v_now
   WHERE id = p_opportunity_id
   RETURNING * INTO v_updated;

  -- Insert immutable transition row.
  INSERT INTO stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) VALUES (
    v_company_id, p_opportunity_id, v_from_stage, p_to_stage,
    v_now, p_user_id, v_now - v_prior_entered_at
  );

  RETURN v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION public.move_opportunity_stage(uuid, text, uuid) TO authenticated;
