-- Auto-advance new_lead → qualifying when the first Activity is logged.
--
-- Closes the gap between bible §10:205 (documented behavior) and prod.
-- The LEADS tab rebuild verification (P1-1) confirmed zero historical
-- system-triggered new_lead → qualifying transitions: every transition in
-- production stage_transitions was user-initiated. The documented auto-advance
-- never existed despite being canonical. iOS Phase 4 (LeadLogActivitySheet)
-- writes activities expecting this trigger to fire — without it, logging an
-- activity on a fresh new_lead leaves the lead stuck at new_lead.
--
-- Server-side trigger over client-side advance: a server trigger covers iOS,
-- the web app, and any future client uniformly. Putting it in iOS would also
-- race itself when both clients log activities concurrently.
--
-- Behavior:
--   AFTER INSERT on activities, FOR EACH ROW —
--     if NEW.opportunity_id is set, the opportunity exists, is not soft-deleted,
--     and is currently in 'new_lead', then UPDATE opportunities to 'qualifying'
--     (stage_entered_at=now, stage_manually_set=false) and INSERT a
--     stage_transitions row mirroring the move_opportunity_stage RPC's column set
--     (2026-05-07-01-move-opportunity-stage-rpc.sql).
--
-- Idempotency: the UPDATE's `WHERE stage='new_lead'` is the guard. If the opp
-- has already advanced (any client, any path), the UPDATE matches zero rows
-- and FOUND is false — no stage_transitions row is inserted. Re-running a
-- duplicate activity insert on a now-qualifying opp does nothing.
--
-- stage_manually_set=false marks this advance as system-driven (distinct from
-- the manual drag-on-Kanban path which sets it true via move_opportunity_stage).
-- Downstream analytics that filter for organic vs. manual progression rely on
-- this flag.
--
-- Race coexistence with move_opportunity_stage RPC: the RPC manually advances
-- stages and writes its own stage_transitions row with stage_manually_set=true.
-- This trigger fires on activity inserts. In the only overlap scenario — a
-- user manually advances new_lead → qualifying via the RPC at the same time
-- they log the first activity — Postgres serializes the writes: whichever
-- commits first wins, the other's stage UPDATE matches zero rows (because the
-- target opp is no longer in new_lead), and the conflict resolves cleanly with
-- exactly one stage_transitions row. The trigger never double-inserts.
--
-- SECURITY DEFINER: the trigger function must write opportunities and
-- stage_transitions regardless of the inserting client's RLS posture. Authorization
-- is upstream — the activity INSERT that fires the trigger has already passed
-- the activities company_isolation RLS policy, which proves the inserting user
-- can write under NEW.company_id. The trigger inherits that authorization.
--
-- Historical backfill: deliberately out of scope. Leads created before this
-- migration that already had activities logged stay at their current stage.
-- A retroactive sweep would require introspecting each opp's full activity
-- history to decide whether they would have auto-advanced under this rule,
-- risking incorrect attribution of historic transitions. If desired, that's
-- a separate ticket.
--
-- Schema reference (verified against
-- OPS-Web/src/lib/types/database.types.ts — generated from live Supabase
-- introspection — and OPS-Web/supabase/migrations/EXECUTED/001_pipeline_schema.sql):
--   activities.created_by         UUID NULLABLE  (NOT text — type changed in
--                                                 brief sketch; brief was wrong)
--   activities.opportunity_id     UUID NULLABLE (FK opportunities.id)
--   activities.company_id         UUID NOT NULL
--   activities.created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
--   opportunities.stage           TEXT NOT NULL
--   opportunities.stage_entered_at TIMESTAMPTZ NOT NULL
--   opportunities.stage_manually_set BOOLEAN NOT NULL
--   opportunities.deleted_at      TIMESTAMPTZ NULLABLE
--   stage_transitions.transitioned_by UUID NULLABLE
--   stage_transitions.duration_in_stage INTERVAL NULLABLE
--   stage_transitions has NO created_at column (verified)

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
  -- Non-opportunity activities (client-only notes, system events without an
  -- opp link, etc.) contribute nothing here. Bail before doing any I/O.
  IF NEW.opportunity_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Read the opp's current stage + prior stage entry timestamp. SECURITY
  -- DEFINER means RLS does not gate this SELECT — authorization for the
  -- underlying activity insert already validated the operator's access.
  SELECT company_id, stage, stage_entered_at
    INTO v_company_id, v_current_stage, v_stage_entered_at
    FROM opportunities
   WHERE id = NEW.opportunity_id
     AND deleted_at IS NULL;

  -- Opp not found (was deleted between activity insert and trigger fire — rare
  -- but possible) or already past new_lead. Nothing to do.
  IF v_company_id IS NULL OR v_current_stage <> 'new_lead' THEN
    RETURN NEW;
  END IF;

  -- Advance to qualifying. The `AND stage='new_lead'` clause is the
  -- idempotency guard: if a sibling client advanced this opp between our
  -- SELECT above and this UPDATE, the WHERE matches zero rows and we skip
  -- the stage_transitions insert entirely.
  UPDATE opportunities
     SET stage              = 'qualifying',
         stage_entered_at   = NEW.created_at,
         stage_manually_set = false,
         updated_at         = NEW.created_at
   WHERE id = NEW.opportunity_id
     AND stage = 'new_lead';

  -- FOUND is true only when the UPDATE matched a row — i.e. we actually
  -- made the new_lead → qualifying transition ourselves.
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

-- Drop-and-recreate is safe: this trigger does not exist in prod (P1-1
-- verification confirmed no system-triggered transitions ever fired).
DROP TRIGGER IF EXISTS tr_activities_first_log_auto_advance ON public.activities;

CREATE TRIGGER tr_activities_first_log_auto_advance
AFTER INSERT ON public.activities
FOR EACH ROW
EXECUTE FUNCTION public.tr_activity_first_log_auto_advance();
