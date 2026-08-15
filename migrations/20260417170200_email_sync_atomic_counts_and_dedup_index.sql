-- ──────────────────────────────────────────────────────────────────────────
-- B25: Atomic correspondence count increment
-- B43: Unique partial index on activities.email_message_id
-- ──────────────────────────────────────────────────────────────────────────
--
-- B25: Previously sync-engine.updateCorrespondenceCounts did a read-modify-
-- write pattern: SELECT count, increment in app, UPDATE. Two concurrent
-- sync jobs for the same opportunity would both read count=N, both write
-- N+1 instead of N+2 — counts silently drifted low on busy mailboxes.
--
-- This RPC performs the increment atomically under a row lock. Returns a
-- single-row table containing the updated values so the caller can run
-- StageEvaluator on the new counts without a second SELECT.
--
-- The function also:
--   - Advances last_inbound_at / last_outbound_at only if the incoming
--     email is strictly newer than the current timestamp.
--   - Clears stage_manually_set on inbound (situation evolved, AI is
--     allowed to re-evaluate).
--   - Bumps last_activity_at unconditionally.

CREATE OR REPLACE FUNCTION public.increment_opportunity_correspondence(
  p_opportunity_id uuid,
  p_is_inbound boolean,
  p_email_date timestamptz
) RETURNS TABLE (
  correspondence_count integer,
  inbound_count integer,
  outbound_count integer,
  stage text,
  stage_manually_set boolean,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.opportunities o
  SET
    correspondence_count = COALESCE(o.correspondence_count, 0) + 1,
    inbound_count = COALESCE(o.inbound_count, 0) + (CASE WHEN p_is_inbound THEN 1 ELSE 0 END),
    outbound_count = COALESCE(o.outbound_count, 0) + (CASE WHEN p_is_inbound THEN 0 ELSE 1 END),
    last_message_direction = CASE WHEN p_is_inbound THEN 'in' ELSE 'out' END,
    last_activity_at = p_email_date,
    last_inbound_at = CASE
      WHEN p_is_inbound AND (o.last_inbound_at IS NULL OR p_email_date > o.last_inbound_at)
        THEN p_email_date
      ELSE o.last_inbound_at
    END,
    last_outbound_at = CASE
      WHEN NOT p_is_inbound AND (o.last_outbound_at IS NULL OR p_email_date > o.last_outbound_at)
        THEN p_email_date
      ELSE o.last_outbound_at
    END,
    stage_manually_set = CASE
      WHEN p_is_inbound AND o.stage_manually_set THEN false
      ELSE o.stage_manually_set
    END,
    updated_at = now()
  WHERE o.id = p_opportunity_id
  RETURNING
    o.correspondence_count,
    o.inbound_count,
    o.outbound_count,
    o.stage,
    o.stage_manually_set,
    o.last_inbound_at,
    o.last_outbound_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_opportunity_correspondence(uuid, boolean, timestamptz)
  TO authenticated, service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- B43: Unique partial index on activities.email_message_id
-- Prevents two concurrent syncs from racing past the `SELECT WHERE
-- email_message_id = ?` dedup check in processInboundEmail/processSentEmail.
-- Partial so non-email activities (type='call', 'note', etc.) where
-- email_message_id is NULL continue to allow any number of rows.

CREATE UNIQUE INDEX IF NOT EXISTS activities_email_message_id_unique
  ON public.activities (email_message_id)
  WHERE email_message_id IS NOT NULL;
