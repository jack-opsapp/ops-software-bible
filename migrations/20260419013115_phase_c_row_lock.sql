-- ─────────────────────────────────────────────────────────────────────────────
-- 070_phase_c_row_lock.sql
-- Phase C Row-Level Execution Lock
--
-- Prevents concurrent runners of the chunked Phase C pipeline from racing on
-- the same gmail_scan_jobs row. Without this, a webhook retry or duplicate
-- /analyze-memory-continue dispatch puts two runners through the same thread
-- range — downstream DB writes are upsert-safe but phaseCStats (in-memory
-- accumulators) and profilesBuilt counts would be clobbered or double-counted
-- by whichever runner finalizes last.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE gmail_scan_jobs
  ADD COLUMN phase_c_lock_holder_id TEXT,
  ADD COLUMN phase_c_lock_expires_at TIMESTAMPTZ;

COMMENT ON COLUMN gmail_scan_jobs.phase_c_lock_holder_id IS
  'Opaque string identifying the Phase C runner holding this row. NULL = no lock. See migration 070_phase_c_row_lock.sql.';
COMMENT ON COLUMN gmail_scan_jobs.phase_c_lock_expires_at IS
  'Wall-clock expiry for phase_c_lock_holder_id. Expired locks are treated as free on next acquisition.';

-- Atomic acquisition. Claims the lock iff currently unheld or expired.
CREATE OR REPLACE FUNCTION acquire_phase_c_lock(
  p_job_id UUID,
  p_holder TEXT,
  p_lease_seconds INT DEFAULT 900
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_rows INT;
BEGIN
  UPDATE gmail_scan_jobs
  SET phase_c_lock_holder_id = p_holder,
      phase_c_lock_expires_at = NOW() + (p_lease_seconds || ' seconds')::INTERVAL
  WHERE id = p_job_id
    AND (phase_c_lock_holder_id IS NULL
         OR phase_c_lock_expires_at < NOW());

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$$;

-- Fenced release. Only clears the lock if the supplied holder still owns it.
CREATE OR REPLACE FUNCTION release_phase_c_lock(
  p_job_id UUID,
  p_holder TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE gmail_scan_jobs
  SET phase_c_lock_holder_id = NULL,
      phase_c_lock_expires_at = NULL
  WHERE id = p_job_id
    AND phase_c_lock_holder_id = p_holder;
END;
$$;
