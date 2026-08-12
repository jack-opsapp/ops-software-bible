-- email_threads.closed_opp_assessment
--
-- Cached AI assessment of whether the latest inbound message on a thread
-- whose linked opportunity is in a terminal stage (won/lost/discarded)
-- references a NEW project (vs a follow-up on the existing closed deal).
--
-- Shape:
--   {
--     "signal": "new_project" | "followup" | "unclear",
--     "assessed_at": "<ISO timestamp>",
--     "assessed_message_at": "<ISO of the message that triggered the assessment>",
--     "reasoning": "<one short sentence>"
--   }
--
-- Cleared (set to NULL) when the linked opportunity moves out of a terminal
-- stage, or when opportunity_id is unset.

ALTER TABLE email_threads
  ADD COLUMN IF NOT EXISTS closed_opp_assessment jsonb DEFAULT NULL;

COMMENT ON COLUMN email_threads.closed_opp_assessment IS
  'AI assessment of new-project relevance for inbound mail on closed opps. {signal, assessed_at, assessed_message_at, reasoning}.';

-- Partial index used by the inbox detail endpoint when surfacing the banner.
CREATE INDEX IF NOT EXISTS email_threads_closed_opp_signal_idx
  ON email_threads ((closed_opp_assessment->>'signal'))
  WHERE closed_opp_assessment IS NOT NULL;
