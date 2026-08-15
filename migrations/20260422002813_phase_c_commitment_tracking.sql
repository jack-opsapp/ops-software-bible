-- Phase C — Commitment date tracking
--
-- Adds due_date + resolved_at to agent_memories and denormalizes the
-- "next unresolved commitment due date" onto email_threads so the inbox
-- can render a COMMITMENTS rail without joining on every list fetch.
--
-- A trigger on agent_memories keeps the email_threads denorm fresh
-- whenever a commitment row is inserted, updated, or deleted.

-- ─── Memory columns ─────────────────────────────────────────────────────────

ALTER TABLE agent_memories
  ADD COLUMN IF NOT EXISTS due_date timestamptz,
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

COMMENT ON COLUMN agent_memories.due_date IS
  'Commitment due timestamp. Populated by Phase C extraction for category=commitment memories, grounded against the source email date. NULL on non-commitment rows.';
COMMENT ON COLUMN agent_memories.resolved_at IS
  'When a commitment was marked resolved. NULL means unresolved — overdue if due_date < now(). Set via the inbox Resolve action or when the parent thread is archived.';

-- ─── Thread-level denormalization ───────────────────────────────────────────

ALTER TABLE email_threads
  ADD COLUMN IF NOT EXISTS next_commitment_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS has_unresolved_commitments boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN email_threads.next_commitment_due_at IS
  'Earliest due_date across this thread''s unresolved commitments. Maintained by the recompute_thread_commitments trigger. NULL when no unresolved commitments.';
COMMENT ON COLUMN email_threads.has_unresolved_commitments IS
  'Denormalized flag — true when at least one agent_memories row with category=commitment, resolved_at IS NULL, due_date IS NOT NULL references this thread.';

-- ─── Indexes ────────────────────────────────────────────────────────────────

-- Partial index for the COMMITMENTS rail — only rows that can appear there.
CREATE INDEX IF NOT EXISTS idx_email_threads_commitments
  ON email_threads (company_id, next_commitment_due_at ASC)
  WHERE has_unresolved_commitments = true;

-- Partial index on agent_memories for the recompute trigger's lookup path
-- and for the per-thread commitment list shown in the detail view pill.
CREATE INDEX IF NOT EXISTS idx_agent_memories_commitment_thread
  ON agent_memories (company_id, source_id, due_date ASC)
  WHERE category = 'commitment' AND due_date IS NOT NULL;

-- ─── Trigger: recompute thread commitment denorm ────────────────────────────
--
-- Fires on agent_memories INSERT/UPDATE/DELETE. Short-circuits unless the
-- affected row is (or was) a commitment. Recomputes next_commitment_due_at
-- and has_unresolved_commitments for each affected thread.
--
-- source_id for agent_memories is text because legacy live-outbound memories
-- use the message date as source_id. The trigger gracefully skips rows whose
-- source_id can't be cast to uuid — those memories don't reference a thread.

CREATE OR REPLACE FUNCTION recompute_thread_commitments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  target_ids text[] := ARRAY[]::text[];
  target_id_text text;
  target_id_uuid uuid;
  next_due timestamptz;
BEGIN
  -- Category gate: skip rows that are neither currently nor previously
  -- commitments. This keeps the trigger cheap for the general agent_memories
  -- insert path (which writes facts, pricing, etc. much more often than
  -- commitments).
  IF TG_OP = 'DELETE' AND OLD.category IS DISTINCT FROM 'commitment' THEN
    RETURN OLD;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.category IS DISTINCT FROM 'commitment' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND OLD.category IS DISTINCT FROM 'commitment'
     AND NEW.category IS DISTINCT FROM 'commitment'
  THEN
    RETURN NEW;
  END IF;

  -- Collect affected source_ids. UPDATEs where source_id changes need to
  -- recompute both old and new threads — rare but correct.
  IF TG_OP = 'DELETE' THEN
    IF OLD.source_id IS NOT NULL THEN target_ids := target_ids || OLD.source_id; END IF;
  ELSIF TG_OP = 'INSERT' THEN
    IF NEW.source_id IS NOT NULL THEN target_ids := target_ids || NEW.source_id; END IF;
  ELSE
    IF NEW.source_id IS NOT NULL THEN target_ids := target_ids || NEW.source_id; END IF;
    IF OLD.source_id IS NOT NULL AND OLD.source_id IS DISTINCT FROM NEW.source_id THEN
      target_ids := target_ids || OLD.source_id;
    END IF;
  END IF;

  FOREACH target_id_text IN ARRAY target_ids
  LOOP
    BEGIN
      target_id_uuid := target_id_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      -- Legacy live-path memory; source_id is a date string, not a thread id.
      CONTINUE;
    END;

    SELECT MIN(due_date) INTO next_due
    FROM agent_memories
    WHERE source_id = target_id_text
      AND category = 'commitment'
      AND due_date IS NOT NULL
      AND resolved_at IS NULL;

    UPDATE email_threads
    SET next_commitment_due_at = next_due,
        has_unresolved_commitments = (next_due IS NOT NULL)
    WHERE id = target_id_uuid;
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_thread_commitments ON agent_memories;
CREATE TRIGGER trg_recompute_thread_commitments
AFTER INSERT OR UPDATE OR DELETE ON agent_memories
FOR EACH ROW
EXECUTE FUNCTION recompute_thread_commitments();

-- ─── Auto-resolve on thread archive ─────────────────────────────────────────
--
-- When a user archives a thread, their outstanding commitments on that
-- thread are no longer actionable — auto-resolve them so the COMMITMENTS
-- rail doesn't show stale rows. Unarchive does NOT re-open commitments
-- (that's destructive); the user can manually unresolve via the detail
-- view if the archive was accidental.

CREATE OR REPLACE FUNCTION auto_resolve_commitments_on_archive()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Only react to the transition null → not-null (the archive event).
  IF OLD.archived_at IS NULL AND NEW.archived_at IS NOT NULL THEN
    UPDATE agent_memories
    SET resolved_at = NEW.archived_at
    WHERE source_id = NEW.id::text
      AND category = 'commitment'
      AND resolved_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_resolve_commitments_on_archive ON email_threads;
CREATE TRIGGER trg_auto_resolve_commitments_on_archive
AFTER UPDATE OF archived_at ON email_threads
FOR EACH ROW
EXECUTE FUNCTION auto_resolve_commitments_on_archive();
