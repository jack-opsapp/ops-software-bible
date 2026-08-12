-- Phase C — extraction marker on email_threads
--
-- Lets the backfill route skip threads it has already attempted, even
-- when the LLM produced zero facts for them (short threads, auto-replies,
-- etc.). Without this, the idempotency filter on agent_memories
-- presence would re-process the same dateless threads on every run.
--
-- Backfill: existing agent_memories rows carry source_id=thread.id, so we
-- can mark any thread with at least one memory as extracted.

ALTER TABLE email_threads
  ADD COLUMN IF NOT EXISTS phase_c_extracted_at timestamptz;

COMMENT ON COLUMN email_threads.phase_c_extracted_at IS
  'Timestamp of the last successful Phase C extraction pass over this thread. NULL = never processed. Set by /api/inbox/phase-c-backfill after each thread.';

CREATE INDEX IF NOT EXISTS idx_email_threads_phase_c_extracted
  ON email_threads (company_id, phase_c_extracted_at)
  WHERE phase_c_extracted_at IS NULL;

-- Backfill: any thread that already has at least one agent_memories row
-- keyed to it has been through extraction, regardless of whether any
-- facts stuck. Use MAX(created_at) so future re-runs have a meaningful
-- timestamp to compare against.
UPDATE email_threads t
SET phase_c_extracted_at = m.last_created
FROM (
  SELECT source_id, MAX(created_at) AS last_created
  FROM agent_memories
  WHERE source_id IS NOT NULL
  GROUP BY source_id
) m
WHERE m.source_id = t.id::text
  AND t.phase_c_extracted_at IS NULL;
