-- move_opportunity_stage: atomic stage move with server-computed duration.
-- Replaces the 3-arg version with a defaulted 4th param so OPS-Web can carry
-- its stage-default win probability through the same atomic transaction.
-- Context: the web client previously updated opportunities + inserted
-- stage_transitions itself, sending raw milliseconds into the interval column
-- (Postgres parses a bare number as SECONDS, inflating every web-recorded
-- duration 1000x), stamping browser-clock timestamps into stage_entered_at,
-- and swallowing history-insert failures. Existing callers are unchanged:
-- iOS calls with 3 named params; book_site_visit and
-- consume_phase_c_bilateral_event_handoff call with 3 positional args — all
-- resolve against the defaulted signature.
-- Also adopts win_linked_opportunity's hardening: FOR UPDATE row lock so
-- concurrent moves serialize (each transition row records the true
-- from_stage), and a loud access_denied when RLS filters the update instead
-- of a silent NULL row.

DROP FUNCTION IF EXISTS public.move_opportunity_stage(uuid, text, uuid);

CREATE FUNCTION public.move_opportunity_stage(
  p_opportunity_id uuid,
  p_to_stage text,
  p_user_id uuid,
  p_win_probability integer DEFAULT NULL
)
RETURNS opportunities
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id uuid;
  v_from_stage text;
  v_prior_entered_at timestamptz;
  v_now timestamptz := now();
  v_updated opportunities;
BEGIN
  -- Read current state under a row lock so concurrent moves serialize and
  -- each transition row records the true from_stage. RLS applies (SECURITY
  -- INVOKER): a caller who cannot see this row selects nothing and gets
  -- opportunity_not_found.
  SELECT company_id, stage, stage_entered_at
    INTO v_company_id, v_from_stage, v_prior_entered_at
    FROM opportunities
   WHERE id = p_opportunity_id
     AND deleted_at IS NULL
   FOR UPDATE;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'opportunity_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- No-op if already in the target stage; still return the row. The win
  -- probability is deliberately not applied on a no-op — callers never send
  -- same-stage moves, and a no-op must not mutate anything.
  IF v_from_stage = p_to_stage THEN
    SELECT * INTO v_updated FROM opportunities WHERE id = p_opportunity_id;
    RETURN v_updated;
  END IF;

  -- Update opportunity: stage + stage_entered_at + manually_set flag, plus
  -- the caller's stage-default win probability when provided (NULL = leave
  -- as-is; the table CHECK enforces 0..100).
  UPDATE opportunities
     SET stage              = p_to_stage,
         stage_entered_at   = v_now,
         stage_manually_set = true,
         win_probability    = COALESCE(p_win_probability, win_probability),
         updated_at         = v_now
   WHERE id = p_opportunity_id
   RETURNING * INTO v_updated;

  -- RLS role_scope_update filters silently (USING, not CHECK, on an
  -- un-editable row): 0 rows updated must be a loud permission error, not a
  -- null row the client fails to decode.
  IF v_updated.id IS NULL THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE = '42501';
  END IF;

  -- Insert immutable transition row (server clock, proper interval).
  INSERT INTO stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) VALUES (
    v_company_id, p_opportunity_id, v_from_stage, p_to_stage,
    v_now, p_user_id, v_now - v_prior_entered_at
  );

  RETURN v_updated;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.move_opportunity_stage(uuid, text, uuid, integer) TO anon, authenticated, service_role;
