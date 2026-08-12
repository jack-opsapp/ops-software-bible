-- Auto-advance new_lead → qualifying when the first Activity is logged.
-- Closes bible §10:205. See ops-software-bible/migrations/2026-05-20-activities-first-log-auto-advance-trigger.sql
-- for the full design rationale, race-coexistence reasoning, and schema verification notes.

CREATE OR REPLACE FUNCTION public.tr_activity_first_log_auto_advance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id       uuid;
  v_current_stage    text;
  v_stage_entered_at timestamptz;
BEGIN
  IF NEW.opportunity_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT company_id, stage, stage_entered_at
    INTO v_company_id, v_current_stage, v_stage_entered_at
    FROM opportunities
   WHERE id = NEW.opportunity_id
     AND deleted_at IS NULL;

  IF v_company_id IS NULL OR v_current_stage <> 'new_lead' THEN
    RETURN NEW;
  END IF;

  UPDATE opportunities
     SET stage              = 'qualifying',
         stage_entered_at   = NEW.created_at,
         stage_manually_set = false,
         updated_at         = NEW.created_at
   WHERE id = NEW.opportunity_id
     AND stage = 'new_lead';

  IF FOUND THEN
    INSERT INTO stage_transitions (
      company_id, opportunity_id, from_stage, to_stage,
      transitioned_at, transitioned_by, duration_in_stage
    ) VALUES (
      v_company_id, NEW.opportunity_id, 'new_lead', 'qualifying',
      NEW.created_at, NEW.created_by, NEW.created_at - v_stage_entered_at
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_activities_first_log_auto_advance ON public.activities;

CREATE TRIGGER tr_activities_first_log_auto_advance
AFTER INSERT ON public.activities
FOR EACH ROW
EXECUTE FUNCTION public.tr_activity_first_log_auto_advance();
